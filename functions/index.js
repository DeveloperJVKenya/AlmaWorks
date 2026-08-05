const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { setGlobalOptions } = require("firebase-functions/v2");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();
setGlobalOptions({ region: "us-central1" });

const MESSAGING_CHUNK_SIZE = 500; // FCM multicast hard limit

/**
 * Fires whenever the app writes to AdminNotificationQueue (client access
 * requests, Inventory checkout requests, etc. — see notification_service.dart
 * and inventory_service.dart's _notifyAdmins()). The app already delivers
 * these in real time to any MainAdmin/Admin device that currently has the
 * app open via a live Firestore listener; this function's only job is the
 * case that listener can't cover — a device where the app isn't running at
 * all — by sending a real FCM push so the OS wakes/notifies it directly.
 *
 * docId is included in the FCM data payload so the client can derive the
 * same stable notification id used by the Firestore-listener path
 * (see lib/rbacsystem/notification_id_util.dart), collapsing the two into a
 * single notification instead of showing a duplicate when a device receives
 * both.
 */
exports.onAdminNotificationQueued = onDocumentCreated(
  "AdminNotificationQueue/{docId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    const docId = event.params.docId;
    const title = data.title || "🔔 New Notification";
    const body = data.body || "";
    const payload = data.payload || {};

    const usersSnap = await admin
      .firestore()
      .collection("Users")
      .where("role", "in", ["MainAdmin", "Admin"])
      .get();

    const tokens = [];
    const tokenToDocId = new Map();
    usersSnap.forEach((doc) => {
      const token = doc.data().fcmToken;
      if (token) {
        tokens.push(token);
        tokenToDocId.set(token, doc.id);
      }
    });

    if (tokens.length === 0) {
      logger.info(`No Admin/MainAdmin FCM tokens found — skipping push for ${docId}`);
      return;
    }

    // Stringify data values — FCM requires all `data` fields to be strings.
    const dataPayload = { docId, title, body };
    for (const [key, value] of Object.entries(payload)) {
      dataPayload[key] = String(value);
    }

    const message = {
      notification: { title, body },
      data: dataPayload,
      android: { priority: "high" },
      apns: { payload: { aps: { sound: "default" } } },
    };

    const staleTokens = [];
    for (let i = 0; i < tokens.length; i += MESSAGING_CHUNK_SIZE) {
      const chunk = tokens.slice(i, i + MESSAGING_CHUNK_SIZE);
      const response = await admin.messaging().sendEachForMulticast({
        ...message,
        tokens: chunk,
      });
      response.responses.forEach((r, idx) => {
        if (
          !r.success &&
          (r.error?.code === "messaging/registration-token-not-registered" ||
            r.error?.code === "messaging/invalid-registration-token")
        ) {
          staleTokens.push(chunk[idx]);
        }
      });
    }

    // Clean up tokens FCM reports as dead so future sends don't keep retrying them.
    if (staleTokens.length > 0) {
      const batch = admin.firestore().batch();
      staleTokens.forEach((token) => {
        const userDocId = tokenToDocId.get(token);
        if (userDocId) {
          batch.update(admin.firestore().collection("Users").doc(userDocId), {
            fcmToken: admin.firestore.FieldValue.delete(),
          });
        }
      });
      await batch.commit();
      logger.info(`Cleared ${staleTokens.length} stale FCM token(s)`);
    }

    logger.info(`Push sent for AdminNotificationQueue/${docId} to ${tokens.length} device(s)`);
  }
);
