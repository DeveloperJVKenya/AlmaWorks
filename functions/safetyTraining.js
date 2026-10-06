/**
 * Safety Training server side (see lib/screens/safety_training):
 *   - submitSafetyScenarioAttempt: grades + records an attempt (the only
 *     way a SafetyTrainingSessions doc is created) and maintains the
 *     worker's SafetyTrainingWorkerStats doc in the same transaction.
 *   - rebuildSafetyTrainingStats: (re)builds every worker's stats doc from
 *     their sessions — run once after deploy for pre-existing history.
 *   - onSafetyTrainingReviewCreated / onSafetyTrainingFeedbackCreated:
 *     notify the worker (and an escalation's named recipient).
 *   - sendWeeklySafetyTrainingReminder / sendSafetyTrainingFollowUps:
 *     scheduled nudges.
 *
 * Requires firebase-admin to be initialized before this module is loaded
 * (index.js does so before requiring it).
 */
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const logger = require("firebase-functions/logger");
const { getFirestore, FieldValue, Timestamp } = require("firebase-admin/firestore");

const db = getFirestore();

const SAFETY_TRAINING_ROLES = ["MainAdmin", "Admin", "SystemAdmin", "Technician"];
const SAFETY_REVIEWER_ROLES = ["MainAdmin", "SystemAdmin"];

/** Who hears about each new attempt: reviewers, plus Admin-tier trainers. */
const SAFETY_ATTEMPT_ALERT_ROLES = ["MainAdmin", "SystemAdmin", "Admin"];

/** Client-generated attempt ids (a Firestore auto-id) — see submitSafetyScenarioAttempt. */
const ATTEMPT_ID_PATTERN = /^[A-Za-z0-9]{10,40}$/;
const SAFETY_REASONING_MIN_LENGTH = 20;
const SAFETY_REASONING_MAX_LENGTH = 2000;
const SAFETY_MAX_TIME_SECONDS = 24 * 60 * 60;
const DAY_MS = 24 * 60 * 60 * 1000;

/** Must match SafetyTrainingReviewModel.clearanceValidity in the app. */
const CLEARANCE_VALIDITY_DAYS = 90;

/** How close to a retraining due date the daily follow-up starts nudging. */
const RETRAINING_NUDGE_WINDOW_DAYS = 3;

const sessions = () => db.collection("SafetyTrainingSessions");
const statsRef = (uid) => db.doc(`SafetyTrainingWorkerStats/${uid}`);

function formatDate(date) {
  return date.toLocaleDateString("en-GB", {
    timeZone: "Africa/Nairobi",
    day: "numeric",
    month: "short",
    year: "numeric",
  });
}

async function notifyUser(targetUid, title, body, payload) {
  if (!targetUid) return;
  await db.collection("UserNotificationQueue").add({
    targetUid,
    title,
    body,
    payload,
    createdAt: FieldValue.serverTimestamp(),
  });
}

// ── Worker stats ────────────────────────────────────────────────────────

/**
 * Builds a worker's stats doc from their sessions. Only the first attempt
 * at each scenario (earliest completedAt) scores — the same rule as the
 * app's SafetyScoreSummary.fromSessions — so pre-existing sessions,
 * including retries that were once awarded points, are counted correctly.
 */
function computeStats(uid, sessionDocs) {
  const firstAttempts = {};
  const lastAttemptAtByScenario = {};
  let lastAttemptAt = null;
  let workerName = "";
  let workerRole = "";

  for (const data of sessionDocs) {
    const at = data.completedAt;
    if (!at || !data.scenarioId) continue;
    const first = firstAttempts[data.scenarioId];
    if (!first || at.toMillis() < first.at.toMillis()) {
      firstAttempts[data.scenarioId] = {
        correct: data.isCorrect === true,
        points: Number.isInteger(data.pointsEarned) ? data.pointsEarned : 0,
        at,
        sessionId: data.sessionId || "",
      };
    }
    const last = lastAttemptAtByScenario[data.scenarioId];
    if (!last || at.toMillis() > last.toMillis()) lastAttemptAtByScenario[data.scenarioId] = at;
    if (!lastAttemptAt || at.toMillis() > lastAttemptAt.toMillis()) {
      lastAttemptAt = at;
      workerName = data.workerName || workerName;
      workerRole = data.workerRole || workerRole;
    }
  }
  return withTotals({
    workerUid: uid,
    workerName,
    workerRole,
    totalAttempts: sessionDocs.length,
    firstAttempts,
    lastAttemptAtByScenario,
    lastAttemptAt,
  });
}

function withTotals(stats) {
  const firsts = Object.values(stats.firstAttempts);
  return {
    ...stats,
    scenariosAttempted: firsts.length,
    firstTryCorrect: firsts.filter((f) => f.correct).length,
    totalPoints: firsts.reduce((sum, f) => sum + f.points, 0),
    updatedAt: Timestamp.now(),
  };
}

/** A session's data plus its doc id, as computeStats expects. */
const sessionWithId = (doc) => ({ ...doc.data(), sessionId: doc.id });

/** Recomputes one worker's stats doc from their sessions, transactionally. */
async function rebuildWorkerStats(uid) {
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(sessions().where("workerUid", "==", uid));
    tx.set(statsRef(uid), computeStats(uid, snap.docs.map(sessionWithId)));
  });
}

async function callerRole(uid) {
  const snap = await db.doc(`UserRoles/${uid}`).get();
  return snap.exists ? snap.data().role : null;
}

// ── Grading ─────────────────────────────────────────────────────────────

/**
 * Grades and records one scenario attempt. This is the only path a
 * SafetyTrainingSessions doc can be created by (firestore.rules denies
 * client creates): the correct answer lives in the admin-only
 * SafetyTrainingAnswerKeys collection, so the client never sees it before
 * answering, and isCorrect/pointsEarned/worker identity are all derived
 * here rather than trusted from the caller.
 *
 * Only a worker's first attempt at a scenario scores: it's the honest
 * measure of whether they spotted the hazard, while later attempts — after
 * seeing the answer — are practice. The first-attempt check and the
 * session + stats writes share one transaction on the worker's stats doc,
 * so two simultaneous submissions can't both count as "first".
 *
 * Falls back to the legacy correctOptionIndex/explanation fields on the
 * scenario doc for scenarios not yet migrated to answer keys
 * (SafetyTrainingService.secureLegacyScenarios).
 *
 * Idempotent per `attemptId`: the app generates the session doc id up
 * front and also watches that doc, so the result screen appears as soon as
 * the session is written even if this call's response is slow or lost —
 * and a retry with the same id returns the recorded result instead of
 * grading (and scoring) the attempt twice.
 *
 * Every new attempt is announced to reviewers/trainers through
 * AdminNotificationQueue (pushed by onAdminNotificationQueued).
 */
exports.submitSafetyScenarioAttempt = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "Sign in to submit a safety scenario.");
  }

  const data = request.data || {};
  const scenarioId = typeof data.scenarioId === "string" ? data.scenarioId.trim() : "";
  const selectedOptionIndex = data.selectedOptionIndex;
  const reasoningAnswer = typeof data.reasoningAnswer === "string" ? data.reasoningAnswer.trim() : "";
  const projectId = typeof data.projectId === "string" ? data.projectId.slice(0, 200) : null;
  const projectName = typeof data.projectName === "string" ? data.projectName.slice(0, 300) : null;
  const rawTime = Number.isFinite(data.timeTakenSeconds) ? Math.floor(data.timeTakenSeconds) : 0;
  const timeTakenSeconds = Math.min(Math.max(rawTime, 0), SAFETY_MAX_TIME_SECONDS);
  const attemptId = data.attemptId === undefined || data.attemptId === null ? null : data.attemptId;
  if (attemptId !== null && (typeof attemptId !== "string" || !ATTEMPT_ID_PATTERN.test(attemptId))) {
    throw new HttpsError("invalid-argument", "attemptId must be 10-40 letters or digits.");
  }

  if (!scenarioId || scenarioId.includes("/")) {
    throw new HttpsError("invalid-argument", "A valid scenarioId is required.");
  }
  if (!Number.isInteger(selectedOptionIndex)) {
    throw new HttpsError("invalid-argument", "selectedOptionIndex must be an integer.");
  }
  if (reasoningAnswer.length < SAFETY_REASONING_MIN_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `Please explain your reasoning in at least ${SAFETY_REASONING_MIN_LENGTH} characters.`
    );
  }
  if (reasoningAnswer.length > SAFETY_REASONING_MAX_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `Reasoning answer must be at most ${SAFETY_REASONING_MAX_LENGTH} characters.`
    );
  }

  const [roleSnap, usersSnap, scenarioSnap, keySnap] = await Promise.all([
    db.doc(`UserRoles/${uid}`).get(),
    db.collection("Users").where("uid", "==", uid).limit(1).get(),
    db.doc(`SafetyTrainingScenarios/${scenarioId}`).get(),
    db.doc(`SafetyTrainingAnswerKeys/${scenarioId}`).get(),
  ]);

  const role = roleSnap.exists ? roleSnap.data().role : null;
  if (!SAFETY_TRAINING_ROLES.includes(role)) {
    throw new HttpsError("permission-denied", "Your role cannot take safety training.");
  }
  if (!scenarioSnap.exists) {
    throw new HttpsError("not-found", "This scenario no longer exists.");
  }

  const scenario = scenarioSnap.data();
  if (scenario.isActive === false) {
    throw new HttpsError("failed-precondition", "This scenario has been deactivated.");
  }

  const options = Array.isArray(scenario.options) ? scenario.options : [];
  if (options.length < 2) {
    throw new HttpsError("failed-precondition", "This scenario is incomplete. Please tell an admin.");
  }
  if (selectedOptionIndex < 0 || selectedOptionIndex >= options.length) {
    throw new HttpsError("invalid-argument", "Selected option is out of range.");
  }

  const key = keySnap.exists ? keySnap.data() : scenario;
  const correctOptionIndex = key.correctOptionIndex;
  if (!Number.isInteger(correctOptionIndex) || correctOptionIndex < 0 || correctOptionIndex >= options.length) {
    logger.error(`submitSafetyScenarioAttempt: scenario ${scenarioId} has no valid answer key`);
    throw new HttpsError("failed-precondition", "This scenario's answer key is misconfigured. Please tell an admin.");
  }
  const explanation = typeof key.explanation === "string" ? key.explanation : "";
  const isCorrect = selectedOptionIndex === correctOptionIndex;
  const points = Number.isInteger(scenario.points) && scenario.points > 0 ? scenario.points : 0;

  // Users docs are keyed by the user's display name (matching the app's
  // own `_userName = snap.docs.first.id` convention).
  const workerName = usersSnap.empty ? "" : usersSnap.docs[0].id;
  const sessionRef = attemptId ? sessions().doc(attemptId) : sessions().doc();

  const result = await db.runTransaction(async (tx) => {
    const existingSnap = await tx.get(sessionRef);
    if (existingSnap.exists) {
      // A retry of an attempt that was already recorded — return it as is.
      const existing = existingSnap.data();
      if (existing.workerUid !== uid) {
        throw new HttpsError("already-exists", "This attempt id is already in use.");
      }
      return {
        replayed: true,
        isCorrect: existing.isCorrect === true,
        isFirstAttempt: existing.isFirstAttempt !== false,
        pointsEarned: Number.isInteger(existing.pointsEarned) ? existing.pointsEarned : 0,
        correctOptionIndex: existing.correctOptionIndex,
        explanation: typeof existing.explanation === "string" ? existing.explanation : explanation,
      };
    }

    const statsSnap = await tx.get(statsRef(uid));
    // A worker's first submission since stats docs existed: build their
    // stats from any earlier sessions inside this same transaction.
    const stats = statsSnap.exists
      ? statsSnap.data()
      : computeStats(uid, (await tx.get(sessions().where("workerUid", "==", uid))).docs.map(sessionWithId));

    const isFirstAttempt = !(stats.firstAttempts && stats.firstAttempts[scenarioId]);
    const pointsEarned = isCorrect && isFirstAttempt ? points : 0;
    const completedAt = Timestamp.now();

    tx.set(sessionRef, {
      scenarioId,
      scenarioTitle: scenario.title || "",
      category: scenario.category || "General",
      ...(projectId ? { projectId } : {}),
      ...(projectName ? { projectName } : {}),
      workerUid: uid,
      workerName,
      workerRole: role,
      selectedOptionIndex,
      isCorrect,
      isFirstAttempt,
      reasoningAnswer,
      pointsEarned,
      timeTakenSeconds,
      // Snapshot of the question as it was answered, so this record stays
      // readable even if an admin later edits the scenario.
      question: scenario.question || "",
      options,
      correctOptionIndex,
      // Shown on the result screen; stored here (the worker can only read
      // their own sessions, and only after answering) so the app can render
      // the result straight from this doc — see the idempotency note above.
      explanation,
      serverGraded: true,
      completedAt,
    });

    const firstAttempts = { ...(stats.firstAttempts || {}) };
    if (isFirstAttempt) {
      firstAttempts[scenarioId] = { correct: isCorrect, points: pointsEarned, at: completedAt, sessionId: sessionRef.id };
    }
    tx.set(statsRef(uid), withTotals({
      workerUid: uid,
      workerName: workerName || stats.workerName || "",
      workerRole: role,
      totalAttempts: (stats.totalAttempts || 0) + 1,
      firstAttempts,
      lastAttemptAtByScenario: { ...(stats.lastAttemptAtByScenario || {}), [scenarioId]: completedAt },
      lastAttemptAt: completedAt,
    }));

    return { replayed: false, isCorrect, isFirstAttempt, pointsEarned, correctOptionIndex, explanation };
  });

  if (!result.replayed) {
    await notifyAttemptToReviewers({
      sessionId: sessionRef.id,
      workerUid: uid,
      workerName,
      scenarioId,
      scenarioTitle: scenario.title || "a scenario",
      isCorrect,
      isFirstAttempt: result.isFirstAttempt,
    });
  }

  logger.info(
    `submitSafetyScenarioAttempt: ${uid} answered ${scenarioId} (correct: ${result.isCorrect}, ` +
      `first: ${result.isFirstAttempt}, replayed: ${result.replayed}) -> ${sessionRef.id}`
  );

  return {
    sessionId: sessionRef.id,
    isCorrect: result.isCorrect,
    isFirstAttempt: result.isFirstAttempt,
    pointsEarned: result.pointsEarned,
    correctOptionIndex: result.correctOptionIndex,
    explanation: result.explanation,
  };
});

/**
 * Tells reviewers and trainers a worker just submitted an attempt. Best
 * effort: the attempt is already recorded, so a failure here is logged
 * rather than failing the worker's submission.
 */
async function notifyAttemptToReviewers(attempt) {
  const who = attempt.workerName || "A worker";
  const outcome = attempt.isCorrect ? "answered correctly" : "answered incorrectly";
  const kind = attempt.isFirstAttempt ? "" : " (practice attempt)";
  try {
    await db.collection("AdminNotificationQueue").add({
      title: "🦺 New Safety Training Attempt",
      body: `${who} ${outcome} on "${attempt.scenarioTitle}"${kind}. Tap to review their reasoning.`,
      targetRoles: SAFETY_ATTEMPT_ALERT_ROLES,
      payload: {
        type: "safety_training_attempt",
        audience: "reviewer",
        sessionId: attempt.sessionId,
        workerUid: attempt.workerUid,
        workerName: attempt.workerName || "",
        scenarioId: attempt.scenarioId,
      },
      readBy: [],
      isRead: false,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (e) {
    logger.error(`submitSafetyScenarioAttempt: failed to notify reviewers of ${attempt.sessionId}`, e);
  }
}

/**
 * Rebuilds every worker's SafetyTrainingWorkerStats doc from their
 * sessions and stamps SafetyTrainingMeta/stats. Idempotent. Reviewer-only;
 * the review screen calls it automatically when that stamp is missing
 * (i.e. the first time after this feature is deployed).
 */
exports.rebuildSafetyTrainingStats = onCall({ timeoutSeconds: 300 }, async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw new HttpsError("unauthenticated", "Sign in first.");
  if (!SAFETY_REVIEWER_ROLES.includes(await callerRole(uid))) {
    throw new HttpsError("permission-denied", "Only MainAdmin/SystemAdmin can rebuild training statistics.");
  }

  const workerUids = new Set();
  const snap = await sessions().select("workerUid").get();
  for (const doc of snap.docs) {
    const workerUid = doc.get("workerUid");
    if (typeof workerUid === "string" && workerUid) workerUids.add(workerUid);
  }
  for (const workerUid of workerUids) {
    await rebuildWorkerStats(workerUid);
  }
  await db.doc("SafetyTrainingMeta/stats").set({
    rebuiltAt: FieldValue.serverTimestamp(),
    rebuiltByUid: uid,
    workers: workerUids.size,
  });
  logger.info(`rebuildSafetyTrainingStats: rebuilt stats for ${workerUids.size} worker(s)`);
  return { workers: workerUids.size };
});

// ── Notifications ───────────────────────────────────────────────────────

function clearanceExpiry(review) {
  if (review.expiresAt) return review.expiresAt.toDate();
  return new Date(review.reviewedAt.toDate().getTime() + CLEARANCE_VALIDITY_DAYS * DAY_MS);
}

/**
 * Tells the worker about a new determination on their standing, and —
 * for an escalation — the reviewer it was escalated to.
 */
exports.onSafetyTrainingReviewCreated = onDocumentCreated(
  "SafetyTrainingReviews/{reviewId}",
  async (event) => {
    const review = event.data && event.data.data();
    if (!review || !review.workerUid) return;
    const payload = { type: "safety_training_review", reviewId: event.params.reviewId };

    let body;
    switch (review.status) {
      case "cleared":
        body = `You've been cleared to work on site until ${formatDate(clearanceExpiry(review))}.`;
        break;
      case "needsRetraining": {
        const count = Array.isArray(review.assignedScenarioIds) ? review.assignedScenarioIds.length : 0;
        const due = review.dueAt ? ` by ${formatDate(review.dueAt.toDate())}` : "";
        body = `You've been assigned ${count} scenario${count === 1 ? "" : "s"} to retrain on${due}.`;
        break;
      }
      case "escalated":
        body = "Your safety training standing has been escalated for follow-up with a supervisor.";
        break;
      default:
        return;
    }
    await notifyUser(review.workerUid, "🦺 Safety Training Review", body, payload);

    if (review.status === "escalated" && review.escalatedToUid) {
      await notifyUser(
        review.escalatedToUid,
        "⚠️ Safety Escalation",
        `${review.reviewedByName || "A reviewer"} escalated ${review.workerName || "a worker"}'s safety ` +
          "training standing to you for follow-up.",
        { type: "safety_training_escalation", audience: "reviewer", reviewId: event.params.reviewId }
      );
    }
  }
);

/** Tells the worker a trainer commented on one of their answers. */
exports.onSafetyTrainingFeedbackCreated = onDocumentCreated(
  "SafetyTrainingFeedback/{feedbackId}",
  async (event) => {
    const feedback = event.data && event.data.data();
    if (!feedback || !feedback.workerUid) return;
    const comment = String(feedback.comment || "");
    await notifyUser(
      feedback.workerUid,
      `💬 Feedback on "${feedback.scenarioTitle || "a safety scenario"}"`,
      `${feedback.byName || "Your trainer"}: ${comment.length > 140 ? `${comment.slice(0, 137)}…` : comment}`,
      { type: "safety_training_feedback", sessionId: feedback.sessionId || "" }
    );
  }
);

// ── Scheduled nudges ────────────────────────────────────────────────────

/** Each worker's latest review (current standing), keyed by workerUid. */
async function latestReviewsByWorker() {
  const snap = await db.collection("SafetyTrainingReviews").orderBy("reviewedAt", "desc").get();
  const latest = new Map();
  for (const doc of snap.docs) {
    const review = doc.data();
    if (review.workerUid && !latest.has(review.workerUid)) latest.set(review.workerUid, review);
  }
  return latest;
}

async function activeScenarioIds() {
  const snap = await db.collection("SafetyTrainingScenarios").where("isActive", "==", true).select().get();
  return new Set(snap.docs.map((d) => d.id));
}

/**
 * Assigned retraining scenarios not yet attempted since the review that
 * assigned them. Deactivated scenarios are skipped — they can't be played.
 * Must match RetrainingProgress in the app.
 */
function remainingRetraining(review, stats, activeIds) {
  const reviewedAt = review.reviewedAt.toMillis();
  const lastByScenario = (stats && stats.lastAttemptAtByScenario) || {};
  return (review.assignedScenarioIds || []).filter((id) => {
    if (!activeIds.has(id)) return false;
    const last = lastByScenario[id];
    return !last || last.toMillis() <= reviewedAt;
  });
}

/**
 * Weekly check-in for every Technician — deliberately unconditional (an
 * ongoing "gauge your own fitness to work safely" habit, not a catch-up
 * reminder), but tailored to their current standing.
 */
exports.sendWeeklySafetyTrainingReminder = onSchedule(
  { schedule: "0 7 * * 1", timeZone: "Africa/Nairobi" },
  async () => {
    const techniciansSnap = await db.collection("Users").where("role", "==", "Technician").get();
    if (techniciansSnap.empty) {
      logger.info("sendWeeklySafetyTrainingReminder: no Technicians found");
      return;
    }
    const [latestReviews, activeIds] = await Promise.all([latestReviewsByWorker(), activeScenarioIds()]);

    let sent = 0;
    for (const doc of techniciansSnap.docs) {
      const uid = doc.data().uid;
      if (!uid) continue;
      const review = latestReviews.get(uid);
      let body =
        "Take a few minutes this week to run through your safety scenarios and check how fit you are to work safely on site.";
      if (review && review.status === "needsRetraining") {
        const stats = (await statsRef(uid).get()).data();
        const remaining = remainingRetraining(review, stats, activeIds);
        if (remaining.length > 0) {
          const due = review.dueAt ? ` by ${formatDate(review.dueAt.toDate())}` : "";
          body = `You still have ${remaining.length} assigned retraining scenario${remaining.length === 1 ? "" : "s"} ` +
            `to complete${due}.`;
        }
      }
      await notifyUser(uid, "🦺 Weekly Safety Training", body, { type: "safety_training_weekly_reminder" });
      sent += 1;
    }
    logger.info(`sendWeeklySafetyTrainingReminder: sent ${sent} reminder(s)`);
  }
);

/**
 * Daily follow-up on review determinations:
 *   - retraining due within RETRAINING_NUDGE_WINDOW_DAYS or overdue →
 *     nudge the worker (daily until done); the day it becomes overdue,
 *     also tell the reviewer who assigned it.
 *   - clearance expiring today → tell the worker and the reviewer who
 *     granted it, so a fresh review can be scheduled.
 */
exports.sendSafetyTrainingFollowUps = onSchedule(
  { schedule: "0 7 * * *", timeZone: "Africa/Nairobi" },
  async () => {
    const now = Date.now();
    const [latestReviews, activeIds] = await Promise.all([latestReviewsByWorker(), activeScenarioIds()]);
    let sent = 0;

    for (const [uid, review] of latestReviews) {
      if (review.status === "needsRetraining" && review.dueAt) {
        const stats = (await statsRef(uid).get()).data();
        const remaining = remainingRetraining(review, stats, activeIds);
        if (remaining.length === 0) continue;
        const dueMs = review.dueAt.toMillis();
        const dueText = formatDate(review.dueAt.toDate());
        const count = `${remaining.length} retraining scenario${remaining.length === 1 ? "" : "s"}`;

        if (dueMs < now) {
          await notifyUser(uid, "⏰ Retraining Overdue", `Your ${count} ${remaining.length === 1 ? "was" : "were"} due on ${dueText}. ` +
            `Please complete ${remaining.length === 1 ? "it" : "them"} today.`,
            { type: "safety_training_retraining_overdue" });
          sent += 1;
          if (dueMs >= now - DAY_MS) {
            await notifyUser(review.reviewedByUid, "⏰ Retraining Overdue",
              `${review.workerName || "A worker"} hasn't finished their ${count} (due ${dueText}).`,
              { type: "safety_training_retraining_overdue", audience: "reviewer", workerUid: uid });
            sent += 1;
          }
        } else if (dueMs - now <= RETRAINING_NUDGE_WINDOW_DAYS * DAY_MS) {
          await notifyUser(uid, "🦺 Retraining Due Soon", `You have ${count} to complete by ${dueText}.`,
            { type: "safety_training_retraining_due" });
          sent += 1;
        }
      } else if (review.status === "cleared" && review.reviewedAt) {
        const expiresMs = clearanceExpiry(review).getTime();
        if (expiresMs <= now && expiresMs > now - DAY_MS) {
          await notifyUser(uid, "🦺 Safety Clearance Expired",
            "Your safety clearance has expired. Keep practising your scenarios — a reviewer will reassess your standing.",
            { type: "safety_training_clearance_expired" });
          await notifyUser(review.reviewedByUid, "🦺 Safety Clearance Expired",
            `${review.workerName || "A worker"}'s safety clearance expired today and needs a new review.`,
            { type: "safety_training_clearance_expired", audience: "reviewer", workerUid: uid });
          sent += 2;
        }
      }
    }
    logger.info(`sendSafetyTrainingFollowUps: sent ${sent} notification(s)`);
  }
);
