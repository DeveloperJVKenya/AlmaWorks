const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { setGlobalOptions } = require("firebase-functions/v2");
const logger = require("firebase-functions/logger");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

// firebase-admin v13+ dropped the old `admin.firestore()` / `admin.messaging()`
// default-namespace API (it's simply undefined now, not just deprecated) —
// this modular form (getFirestore()/getMessaging()/FieldValue from their own
// submodules) is the only one that still works against the installed
// firebase-admin@14.x.
initializeApp();
setGlobalOptions({ region: "us-central1" });

const db = getFirestore();
const messaging = getMessaging();

const MESSAGING_CHUNK_SIZE = 500; // FCM multicast hard limit
const UID_QUERY_CHUNK_SIZE = 30; // Firestore 'in' query hard limit

/**
 * Collects every FCM token registered for a user doc — the multi-device
 * `fcmTokens` map (see lib/rbacsystem/notification_service.dart and
 * communication_notification_service.dart's _updateUserToken, which both
 * write here keyed by token so a user signed in on web + mobile
 * simultaneously gets pushed on both) plus the legacy single `fcmToken`
 * field as a fallback for any user doc not yet migrated.
 */
function collectTokensForUser(userData) {
  const tokens = new Set();
  const fcmTokens = userData.fcmTokens;
  if (fcmTokens && typeof fcmTokens === "object") {
    for (const token of Object.keys(fcmTokens)) {
      if (token) tokens.add(token);
    }
  }
  if (userData.fcmToken) tokens.add(userData.fcmToken);
  return Array.from(tokens);
}

/** Clears a single dead token from both the multi-device map and the legacy field. */
async function clearStaleToken(userDocRef, token) {
  const update = {};
  update[`fcmTokens.${token}`] = FieldValue.delete();
  const doc = await userDocRef.get();
  if (doc.exists && doc.data().fcmToken === token) {
    update.fcmToken = FieldValue.delete();
  }
  await userDocRef.update(update);
}

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

    const usersSnap = await db
      .collection("Users")
      .where("role", "in", ["MainAdmin", "Admin"])
      .get();

    const tokens = [];
    const tokenToDocRef = new Map();
    usersSnap.forEach((doc) => {
      for (const token of collectTokensForUser(doc.data())) {
        tokens.push(token);
        tokenToDocRef.set(token, doc.ref);
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
      const response = await messaging.sendEachForMulticast({
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
      for (const token of staleTokens) {
        const userDocRef = tokenToDocRef.get(token);
        if (userDocRef) await clearStaleToken(userDocRef, token);
      }
      logger.info(`Cleared ${staleTokens.length} stale FCM token(s)`);
    }

    logger.info(`Push sent for AdminNotificationQueue/${docId} to ${tokens.length} device(s)`);
  }
);

/**
 * The targeted counterpart to onAdminNotificationQueued — fires whenever
 * InventoryService._notifyUser() (see lib/services/inventory_service.dart)
 * writes to UserNotificationQueue for one specific person (e.g. "your
 * booked asset is needed back soon"), rather than broadcasting to every
 * Admin/MainAdmin. Looks up that single user's FCM token by targetUid and
 * pushes to just that device.
 */
exports.onUserNotificationQueued = onDocumentCreated(
  "UserNotificationQueue/{docId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    const docId = event.params.docId;
    const targetUid = data.targetUid;
    if (!targetUid) {
      logger.info(`UserNotificationQueue/${docId} has no targetUid — skipping push`);
      return;
    }

    const title = data.title || "🔔 New Notification";
    const body = data.body || "";
    const payload = data.payload || {};

    const usersSnap = await db
      .collection("Users")
      .where("uid", "==", targetUid)
      .limit(1)
      .get();

    if (usersSnap.empty) {
      logger.info(`No Users doc found for targetUid ${targetUid} — skipping push for ${docId}`);
      return;
    }

    const userDoc = usersSnap.docs[0];
    const tokens = collectTokensForUser(userDoc.data());
    if (tokens.length === 0) {
      logger.info(`No FCM token for targetUid ${targetUid} — skipping push for ${docId}`);
      return;
    }

    const dataPayload = { docId, title, body };
    for (const [key, value] of Object.entries(payload)) {
      dataPayload[key] = String(value);
    }

    const response = await messaging.sendEachForMulticast({
      notification: { title, body },
      data: dataPayload,
      tokens,
      android: { priority: "high" },
      apns: { payload: { aps: { sound: "default" } } },
    });

    const staleTokens = [];
    response.responses.forEach((r, idx) => {
      if (
        !r.success &&
        (r.error?.code === "messaging/registration-token-not-registered" ||
          r.error?.code === "messaging/invalid-registration-token")
      ) {
        staleTokens.push(tokens[idx]);
      }
    });
    for (const token of staleTokens) {
      await clearStaleToken(userDoc.ref, token);
    }
    if (staleTokens.length > 0) {
      logger.info(`Cleared ${staleTokens.length} stale FCM token(s) for targetUid ${targetUid}`);
    }

    logger.info(`Push sent for UserNotificationQueue/${docId} to targetUid ${targetUid} (${tokens.length} device(s))`);
  }
);

/**
 * Fires whenever a new Communication message is written (see
 * CommunicationService.sendMessage in
 * lib/screens/communication/communication_service.dart). Pushes every To/Cc
 * recipient — across every device they've registered a token from (see
 * collectTokensForUser) — with wording that differs by whether they were
 * directly addressed (`to`) or just looped in (`cc`), the concrete "behaves
 * like email" requirement for Cc. The sender is never notified of their own
 * message.
 *
 * `data.type = 'communication'` plus `messageId`/`projectId` match exactly
 * what main.dart's AwesomeNotifications tap-routing branch and
 * firebase_notification_handler.dart's background handler already expect,
 * so tapping the push deep-links straight to the message.
 *
 * This replaces the old client-side write to a `NotificationQueue`
 * collection that had no Cloud Function consumer — CommunicationNotification
 * Service.enqueueNotificationsForMessage() has been removed entirely in
 * favor of this trigger, which also can't be spoofed by a malicious client
 * the way a client-written notification doc could be.
 */
exports.onCommunicationMessageCreated = onDocumentCreated(
  "Communication/{messageId}",
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const msg = snap.data();
    const messageId = event.params.messageId;
    const projectId = msg.projectId || "";
    const subject = msg.subject || "(no subject)";
    const fromUid = msg.from && msg.from.uid;
    const fromName = (msg.from && (msg.from.username || msg.from.email)) || "Someone";

    const toUids = (msg.to || []).map((p) => p.uid).filter(Boolean);
    const ccUids = (msg.cc || []).map((p) => p.uid).filter(Boolean);
    const recipientUids = Array.from(new Set([...toUids, ...ccUids])).filter(
      (uid) => uid !== fromUid
    );

    if (recipientUids.length === 0) {
      logger.info(`Communication/${messageId}: no recipients to notify`);
      return;
    }

    const userDocs = [];
    for (let i = 0; i < recipientUids.length; i += UID_QUERY_CHUNK_SIZE) {
      const chunk = recipientUids.slice(i, i + UID_QUERY_CHUNK_SIZE);
      const chunkSnap = await db.collection("Users").where("uid", "in", chunk).get();
      chunkSnap.forEach((d) => userDocs.push(d));
    }

    // One outbound FCM message per (recipient device, To-vs-Cc wording).
    const outbound = []; // { token, ref, message }
    for (const doc of userDocs) {
      const data = doc.data();
      const uid = data.uid;
      const isToRecipient = toUids.includes(uid);
      const title = isToRecipient
        ? `New message from ${fromName}`
        : `${fromName} CC'd you on: ${subject}`;
      const body = isToRecipient ? subject : "Tap to view the conversation.";

      const tokens = collectTokensForUser(data);
      for (const token of tokens) {
        outbound.push({
          token,
          ref: doc.ref,
          message: {
            token,
            notification: { title, body },
            data: { type: "communication", messageId, projectId },
            android: { priority: "high" },
            apns: { payload: { aps: { sound: "default" } } },
          },
        });
      }
    }

    if (outbound.length === 0) {
      logger.info(`Communication/${messageId}: no FCM tokens among recipients`);
      return;
    }

    const staleTokens = []; // { token, ref }
    for (let i = 0; i < outbound.length; i += MESSAGING_CHUNK_SIZE) {
      const chunk = outbound.slice(i, i + MESSAGING_CHUNK_SIZE);
      const response = await messaging.sendEach(chunk.map((o) => o.message));
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

    for (const { token, ref } of staleTokens) {
      await clearStaleToken(ref, token);
    }
    if (staleTokens.length > 0) {
      logger.info(`Cleared ${staleTokens.length} stale FCM token(s) for Communication/${messageId}`);
    }

    logger.info(
      `Push sent for Communication/${messageId} to ${recipientUids.length} recipient(s), ${outbound.length} device(s)`
    );
  }
);

/**
 * Daily sweep (07:00 Africa/Nairobi) that reminds a current asset holder,
 * one day ahead, that another user's booking on that same asset starts
 * tomorrow — the "please plan your return" nudge described in
 * InventoryService.createBooking()'s immediate notification. That immediate
 * notification only fires at the moment the conflicting booking is created;
 * this covers the day-before reminder regardless of when the booking was
 * originally made.
 */
exports.sendBookingReminders = onSchedule(
  { schedule: "0 7 * * *", timeZone: "Africa/Nairobi" },
  async () => {
    const tomorrowStart = new Date();
    tomorrowStart.setDate(tomorrowStart.getDate() + 1);
    tomorrowStart.setHours(0, 0, 0, 0);
    const tomorrowEnd = new Date(tomorrowStart);
    tomorrowEnd.setHours(23, 59, 59, 999);

    const upcomingSnap = await db
      .collection("InventoryAssetBookings")
      .where("status", "==", "scheduled")
      .where("scheduledStart", ">=", tomorrowStart)
      .where("scheduledStart", "<=", tomorrowEnd)
      .get();

    if (upcomingSnap.empty) {
      logger.info("sendBookingReminders: no bookings starting tomorrow");
      return;
    }

    let sent = 0;
    for (const doc of upcomingSnap.docs) {
      const booking = doc.data();

      const activeSnap = await db
        .collection("InventoryAssetBookings")
        .where("assetId", "==", booking.assetId)
        .where("status", "==", "active")
        .limit(1)
        .get();
      if (activeSnap.empty) continue;

      const activeBooking = activeSnap.docs[0].data();
      if (activeBooking.bookedForUid === booking.bookedForUid) continue;

      await db.collection("UserNotificationQueue").add({
        targetUid: activeBooking.bookedForUid,
        title: "⏰ Return Reminder",
        body: `"${booking.assetName}" is booked for ${booking.bookedForName} starting tomorrow — please return it in time.`,
        payload: {
          type: "inventory_booking_reminder",
          assetId: booking.assetId,
          bookingId: doc.id,
        },
        createdAt: FieldValue.serverTimestamp(),
      });
      sent += 1;
    }

    logger.info(`sendBookingReminders: sent ${sent} reminder(s)`);
  }
);
