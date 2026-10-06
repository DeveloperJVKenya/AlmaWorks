const fs = require("fs");
const path = require("path");
const { initializeTestEnvironment, assertFails, assertSucceeds } = require("@firebase/rules-unit-testing");
const {
  doc, getDoc, getDocs, setDoc, updateDoc, deleteDoc, writeBatch, deleteField, addDoc, collection, query, where,
  Timestamp,
} = require("firebase/firestore");
const { ref, uploadBytes, deleteObject, getBytes } = require("firebase/storage");

// Runs under the Firebase emulators — see package.json ("npm test").
const ROOT = path.resolve(__dirname, "..");
const [fsHost, fsPort] = process.env.FIRESTORE_EMULATOR_HOST.split(":");
const [stHost, stPort] = process.env.FIREBASE_STORAGE_EMULATOR_HOST.split(":");

let passed = 0, failed = 0;
async function t(name, fn) {
  try { await fn(); passed++; console.log("PASS", name); }
  catch (e) { failed++; console.log("FAIL", name, "-", e.message); }
}
const REASON = "Because the ladder is not secured at the top.";
const DAY = 24 * 60 * 60 * 1000;

function scenario(extra = {}) {
  return {
    title: "Ladder", category: "Heights", sceneDescription: "x", visualKey: "generic",
    question: "What is the hazard?", options: ["A", "B", "C"], reasoningPrompt: "why",
    difficulty: "Basic", points: 10, isActive: true,
    createdByUid: "admin", createdByName: "Admin", createdByRole: "MainAdmin",
    createdAt: new Date(), updatedAt: new Date(), ...extra,
  };
}

(async () => {
  const env = await initializeTestEnvironment({
    projectId: process.env.GCLOUD_PROJECT,
    firestore: { rules: fs.readFileSync(path.join(ROOT, "firestore.rules"), "utf8"), host: fsHost, port: Number(fsPort) },
    storage: { rules: fs.readFileSync(path.join(ROOT, "storage.rules"), "utf8"), host: stHost, port: Number(stPort) },
  });
  const seed = (fn) => env.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));
  await seed(async (db) => {
    await setDoc(doc(db, "UserRoles/admin"), { role: "MainAdmin" });
    await setDoc(doc(db, "UserRoles/admin2"), { role: "SystemAdmin" });
    await setDoc(doc(db, "UserRoles/plainadmin"), { role: "Admin" });
    await setDoc(doc(db, "UserRoles/tech"), { role: "Technician" });
    await setDoc(doc(db, "UserRoles/tech2"), { role: "Technician" });
    await setDoc(doc(db, "UserRoles/client"), { role: "Client" });
    await setDoc(doc(db, "Users/Tech Person"), { uid: "tech", role: "Technician" });
    await setDoc(doc(db, "SafetyTrainingScenarios/s1"), scenario());
    await setDoc(doc(db, "SafetyTrainingAnswerKeys/s1"), { correctOptionIndex: 2, explanation: "C is right" });
    await setDoc(doc(db, "SafetyTrainingScenarios/legacy"), scenario({ correctOptionIndex: 1, explanation: "B legacy" }));
    await setDoc(doc(db, "SafetyTrainingScenarios/inactive"), scenario({ isActive: false }));
    await setDoc(doc(db, "SafetyTrainingAnswerKeys/inactive"), { correctOptionIndex: 0, explanation: "" });
  });

  const admin = env.authenticatedContext("admin").firestore();
  const plainAdmin = env.authenticatedContext("plainadmin").firestore();
  const tech = env.authenticatedContext("tech").firestore();
  const tech2 = env.authenticatedContext("tech2").firestore();

  // ── Answer key secrecy & session integrity ──
  await t("technician cannot read answer key", () => assertFails(getDoc(doc(tech, "SafetyTrainingAnswerKeys/s1"))));
  await t("technician can read scenario", () => assertSucceeds(getDoc(doc(tech, "SafetyTrainingScenarios/s1"))));
  await t("admin can read answer key", () => assertSucceeds(getDoc(doc(plainAdmin, "SafetyTrainingAnswerKeys/s1"))));
  await t("technician cannot forge a session", () => assertFails(addDoc(collection(tech, "SafetyTrainingSessions"),
    { workerUid: "tech", isCorrect: true, pointsEarned: 99999, scenarioId: "s1" })));
  await t("technician cannot write answer key", () => assertFails(setDoc(doc(tech, "SafetyTrainingAnswerKeys/s1"),
    { correctOptionIndex: 0, explanation: "" })));

  // ── Scenario create / manage ──
  await t("admin creates scenario + key in one batch", () => {
    const b = writeBatch(admin);
    b.set(doc(admin, "SafetyTrainingScenarios/n1"), scenario());
    b.set(doc(admin, "SafetyTrainingAnswerKeys/n1"), { correctOptionIndex: 1, explanation: "e" });
    return assertSucceeds(b.commit());
  });
  await t("scenario without answer key is rejected", () =>
    assertFails(setDoc(doc(admin, "SafetyTrainingScenarios/n2"), scenario())));
  await t("scenario carrying correctOptionIndex is rejected", () => {
    const b = writeBatch(admin);
    b.set(doc(admin, "SafetyTrainingScenarios/n3"), scenario({ correctOptionIndex: 1 }));
    b.set(doc(admin, "SafetyTrainingAnswerKeys/n3"), { correctOptionIndex: 1, explanation: "e" });
    return assertFails(b.commit());
  });
  await t("answer key index out of range is rejected", () => {
    const b = writeBatch(admin);
    b.set(doc(admin, "SafetyTrainingScenarios/n4"), scenario());
    b.set(doc(admin, "SafetyTrainingAnswerKeys/n4"), { correctOptionIndex: 3, explanation: "e" });
    return assertFails(b.commit());
  });
  await t("invalid points (0) rejected", () => {
    const b = writeBatch(admin);
    b.set(doc(admin, "SafetyTrainingScenarios/n5"), scenario({ points: 0 }));
    b.set(doc(admin, "SafetyTrainingAnswerKeys/n5"), { correctOptionIndex: 0, explanation: "e" });
    return assertFails(b.commit());
  });
  await t("createdByUid must be self", () => {
    const b = writeBatch(plainAdmin);
    b.set(doc(plainAdmin, "SafetyTrainingScenarios/n6"), scenario());
    b.set(doc(plainAdmin, "SafetyTrainingAnswerKeys/n6"), { correctOptionIndex: 0, explanation: "e" });
    return assertFails(b.commit());
  });
  await t("admin (plain) toggles isActive", () =>
    assertSucceeds(updateDoc(doc(plainAdmin, "SafetyTrainingScenarios/n1"), { isActive: false, updatedAt: new Date() })));
  await t("technician cannot toggle isActive", () =>
    assertFails(updateDoc(doc(tech, "SafetyTrainingScenarios/n1"), { isActive: true })));
  await t("authorship is immutable", () =>
    assertFails(updateDoc(doc(admin, "SafetyTrainingScenarios/s1"), { createdByUid: "someoneelse" })));
  await t("shrinking options below key index is rejected", () =>
    assertFails(updateDoc(doc(admin, "SafetyTrainingScenarios/s1"), { options: ["A", "B"] })));
  await t("shrinking options with key update in same batch succeeds", () => {
    const b = writeBatch(admin);
    b.update(doc(admin, "SafetyTrainingScenarios/n1"), { options: ["A", "B"] });
    b.set(doc(admin, "SafetyTrainingAnswerKeys/n1"), { correctOptionIndex: 1, explanation: "B now" });
    return assertSucceeds(b.commit());
  });
  await t("legacy scenario toggle blocked until secured", () =>
    assertFails(updateDoc(doc(admin, "SafetyTrainingScenarios/legacy"), { isActive: false })));
  await t("legacy migration batch succeeds", () => {
    const b = writeBatch(admin);
    b.set(doc(admin, "SafetyTrainingAnswerKeys/legacy"), { correctOptionIndex: 1, explanation: "B legacy" });
    b.update(doc(admin, "SafetyTrainingScenarios/legacy"),
      { correctOptionIndex: deleteField(), explanation: deleteField(), updatedAt: new Date() });
    return assertSucceeds(b.commit());
  });
  await t("scenarios still cannot be deleted", () => assertFails(deleteDoc(doc(admin, "SafetyTrainingScenarios/s1"))));

  // ── Reviews ──
  const now = Date.now();
  const review = (extra = {}) => ({
    workerUid: "tech", workerName: "Tech Person", workerRole: "Technician", status: "cleared", notes: "",
    totalAttempts: 1, totalPoints: 10,
    reviewedByUid: "admin", reviewedByName: "Admin", reviewedByRole: "MainAdmin", reviewedAt: new Date(now),
    expiresAt: new Date(now + 90 * DAY), ...extra,
  });
  const addReview = (db, extra) => addDoc(collection(db, "SafetyTrainingReviews"), review(extra));
  await t("clearance with expiry recorded", () => assertSucceeds(addReview(admin)));
  await t("clearance without expiry rejected", () => assertFails(addReview(admin, { expiresAt: null })));
  await t("reviewer cannot review themselves", () => assertFails(addReview(admin, { workerUid: "admin" })));
  await t("unknown status rejected", () => assertFails(addReview(admin, { status: "approved" })));
  await t("oversized notes rejected", () => assertFails(addReview(admin, { notes: "x".repeat(2001) })));
  await t("plain Admin cannot review", () => assertFails(addReview(plainAdmin, { reviewedByUid: "plainadmin" })));
  await t("retraining needs scenarios and due date", async () => {
    await assertFails(addReview(admin, { status: "needsRetraining", expiresAt: null }));
    await assertFails(addReview(admin, { status: "needsRetraining", assignedScenarioIds: [], dueAt: new Date(now + DAY) }));
    await assertSucceeds(addReview(admin, { status: "needsRetraining", assignedScenarioIds: ["s1"], dueAt: new Date(now + DAY) }));
  });
  await t("escalation needs a MainAdmin/SystemAdmin recipient", async () => {
    await assertFails(addReview(admin, { status: "escalated" }));
    await assertFails(addReview(admin, { status: "escalated", escalatedToUid: "plainadmin" }));
    await assertFails(addReview(admin, { status: "escalated", escalatedToUid: "admin" }));
    await assertSucceeds(addReview(admin, { status: "escalated", escalatedToUid: "admin2", escalatedToName: "Admin Two" }));
  });

  // ── Grading Cloud Function + worker stats (real handlers vs the emulator) ──
  const fns = require(path.join(ROOT, "functions/index.js"));
  const call = (uid, data) => fns.submitSafetyScenarioAttempt.run({ auth: uid ? { uid } : undefined, data });
  await seed(async (db) => {
    await setDoc(doc(db, "SafetyTrainingScenarios/legacy2"), scenario({ correctOptionIndex: 0, explanation: "A legacy" }));
    await setDoc(doc(db, "SafetyTrainingScenarios/s2"), scenario({ points: 20 }));
    await setDoc(doc(db, "SafetyTrainingAnswerKeys/s2"), { correctOptionIndex: 0, explanation: "A" });
  });
  const expectCode = async (p, code) => {
    try { await p; } catch (e) { if (e.code === code) return; throw new Error(`expected ${code}, got ${e.code}: ${e.message}`); }
    throw new Error(`expected ${code}, call succeeded`);
  };
  const readAdmin = async (p) => { let d; await seed(async (db) => { d = (await getDoc(doc(db, p))).data(); }); return d; };

  let firstSessionId;
  await t("fn: correct first answer scores, server-graded", async () => {
    const r = await call("tech", { scenarioId: "s1", selectedOptionIndex: 2, reasoningAnswer: REASON, timeTakenSeconds: 12,
      isCorrect: false, pointsEarned: 5 /* ignored */ });
    if (!r.isCorrect || !r.isFirstAttempt || r.pointsEarned !== 10 || r.correctOptionIndex !== 2 || r.explanation !== "C is right") throw new Error(JSON.stringify(r));
    firstSessionId = r.sessionId;
    const s = await readAdmin(`SafetyTrainingSessions/${r.sessionId}`);
    if (s.workerName !== "Tech Person" || s.workerRole !== "Technician" || !s.serverGraded || s.options.length !== 3) throw new Error(JSON.stringify(s));
  });
  await t("fn: session stores explanation; reviewers are alerted", async () => {
    const s = await readAdmin(`SafetyTrainingSessions/${firstSessionId}`);
    if (s.explanation !== "C is right") throw new Error(JSON.stringify(s));
    let alerts = [];
    await seed(async (db) => {
      alerts = (await getDocs(query(collection(db, "AdminNotificationQueue"), where("payload.sessionId", "==", firstSessionId))))
        .docs.map((d) => d.data());
    });
    if (alerts.length !== 1 || alerts[0].payload.type !== "safety_training_attempt"
        || !alerts[0].targetRoles.includes("MainAdmin") || alerts[0].payload.workerUid !== "tech") {
      throw new Error(JSON.stringify(alerts));
    }
  });
  await t("fn: retry with the same attemptId is not recorded twice", async () => {
    const attemptId = "retryAttempt000001";
    const args = { attemptId, scenarioId: "s2", selectedOptionIndex: 1, reasoningAnswer: REASON, timeTakenSeconds: 5 };
    const before = (await readAdmin("SafetyTrainingWorkerStats/tech2"))?.totalAttempts || 0;
    const r1 = await call("tech2", args);
    const r2 = await call("tech2", args);
    const after = (await readAdmin("SafetyTrainingWorkerStats/tech2")).totalAttempts;
    let alerts = 0;
    await seed(async (db) => {
      alerts = (await getDocs(query(collection(db, "AdminNotificationQueue"), where("payload.sessionId", "==", attemptId)))).size;
    });
    if (r1.sessionId !== attemptId || r2.sessionId !== attemptId || r1.isCorrect !== r2.isCorrect
        || r1.pointsEarned !== r2.pointsEarned || after !== before + 1 || alerts !== 1) {
      throw new Error(JSON.stringify({ r1, r2, before, after, alerts }));
    }
  });
  await t("fn: another worker can't reuse an attemptId", () =>
    expectCode(call("tech", { attemptId: "retryAttempt000001", scenarioId: "s2", selectedOptionIndex: 1, reasoningAnswer: REASON }), "already-exists"));
  await t("fn: malformed attemptId rejected", () =>
    expectCode(call("tech", { attemptId: "../bad", scenarioId: "s2", selectedOptionIndex: 1, reasoningAnswer: REASON }), "invalid-argument"));
  await t("worker may watch a not-yet-written attempt, but not read others'", async () => {
    await assertSucceeds(getDoc(doc(tech, "SafetyTrainingSessions/notWrittenYet12345")));
    await assertFails(getDoc(doc(tech, "SafetyTrainingSessions/retryAttempt000001")));
  });
  await t("fn: wrong answer earns 0", async () => {
    const r = await call("tech", { scenarioId: "s2", selectedOptionIndex: 1, reasoningAnswer: REASON, timeTakenSeconds: 5 });
    if (r.isCorrect || r.pointsEarned !== 0 || !r.isFirstAttempt) throw new Error(JSON.stringify(r));
  });
  await t("fn: replaying correctly earns no points", async () => {
    const r = await call("tech", { scenarioId: "s2", selectedOptionIndex: 0, reasoningAnswer: REASON, timeTakenSeconds: 5 });
    if (!r.isCorrect || r.isFirstAttempt || r.pointsEarned !== 0) throw new Error(JSON.stringify(r));
  });
  await t("fn: stats doc maintained in the same transaction", async () => {
    const st = await readAdmin("SafetyTrainingWorkerStats/tech");
    if (st.totalAttempts !== 3 || st.scenariosAttempted !== 2 || st.firstTryCorrect !== 1 || st.totalPoints !== 10
        || st.firstAttempts.s1.sessionId !== firstSessionId || st.firstAttempts.s2.correct !== false
        || !st.lastAttemptAtByScenario.s2) throw new Error(JSON.stringify(st));
  });
  await t("fn: concurrent first attempts — only one scores", async () => {
    const rs = await Promise.all([1, 2, 3].map(() =>
      call("tech2", { scenarioId: "s1", selectedOptionIndex: 2, reasoningAnswer: REASON, timeTakenSeconds: 5 })));
    const firsts = rs.filter((r) => r.isFirstAttempt);
    if (firsts.length !== 1 || rs.reduce((a, r) => a + r.pointsEarned, 0) !== 10) throw new Error(JSON.stringify(rs));
  });
  await t("fn: stats built lazily from pre-existing sessions", async () => {
    await seed(async (db) => {
      await setDoc(doc(db, "UserRoles/old"), { role: "Technician" });
      // Legacy history: wrong first, then a (wrongly) rewarded retry.
      await addDoc(collection(db, "SafetyTrainingSessions"), { workerUid: "old", scenarioId: "s1", isCorrect: false,
        pointsEarned: 0, completedAt: Timestamp.fromMillis(now - 2 * DAY) });
      await addDoc(collection(db, "SafetyTrainingSessions"), { workerUid: "old", scenarioId: "s1", isCorrect: true,
        pointsEarned: 10, completedAt: Timestamp.fromMillis(now - DAY) });
    });
    const r = await call("old", { scenarioId: "s1", selectedOptionIndex: 2, reasoningAnswer: REASON, timeTakenSeconds: 5 });
    const st = await readAdmin("SafetyTrainingWorkerStats/old");
    if (r.isFirstAttempt || r.pointsEarned !== 0 || st.totalAttempts !== 3 || st.totalPoints !== 0 || st.firstTryCorrect !== 0) {
      throw new Error(JSON.stringify({ r, st }));
    }
  });
  await t("fn: legacy scenario falls back to inline key", async () => {
    const r = await call("tech", { scenarioId: "legacy2", selectedOptionIndex: 0, reasoningAnswer: REASON, timeTakenSeconds: 5 });
    if (!r.isCorrect || r.explanation !== "A legacy") throw new Error(JSON.stringify(r));
  });
  await t("fn: too-short reasoning rejected", () => expectCode(call("tech", { scenarioId: "s1", selectedOptionIndex: 0, reasoningAnswer: "too short" }), "invalid-argument"));
  await t("fn: unauthenticated rejected", () => expectCode(call(null, { scenarioId: "s1", selectedOptionIndex: 0, reasoningAnswer: REASON }), "unauthenticated"));
  await t("fn: client role rejected", () => expectCode(call("client", { scenarioId: "s1", selectedOptionIndex: 0, reasoningAnswer: REASON }), "permission-denied"));
  await t("fn: inactive scenario rejected", () => expectCode(call("tech", { scenarioId: "inactive", selectedOptionIndex: 0, reasoningAnswer: REASON }), "failed-precondition"));
  await t("fn: out-of-range option rejected", () => expectCode(call("tech", { scenarioId: "s1", selectedOptionIndex: 7, reasoningAnswer: REASON }), "invalid-argument"));
  await t("fn: missing scenario rejected", () => expectCode(call("tech", { scenarioId: "nope", selectedOptionIndex: 0, reasoningAnswer: REASON }), "not-found"));

  // ── Stats rebuild + stats rules ──
  await t("fn: rebuild is reviewer-only", () => expectCode(fns.rebuildSafetyTrainingStats.run({ auth: { uid: "plainadmin" }, data: {} }), "permission-denied"));
  await t("fn: rebuild recomputes every worker and stamps meta", async () => {
    await seed(async (db) => setDoc(doc(db, "SafetyTrainingWorkerStats/tech"), { workerUid: "tech", totalAttempts: 999 }));
    const r = await fns.rebuildSafetyTrainingStats.run({ auth: { uid: "admin" }, data: {} });
    const st = await readAdmin("SafetyTrainingWorkerStats/tech");
    const meta = await readAdmin("SafetyTrainingMeta/stats");
    if (r.workers < 3 || st.totalAttempts !== 4 || st.totalPoints !== 20 || st.firstTryCorrect !== 2 || !meta || !meta.rebuiltAt) throw new Error(JSON.stringify({ r, st }));
  });
  await t("worker reads own stats, not others'", async () => {
    await assertSucceeds(getDoc(doc(tech, "SafetyTrainingWorkerStats/tech")));
    await assertFails(getDoc(doc(tech, "SafetyTrainingWorkerStats/tech2")));
    await assertSucceeds(getDoc(doc(plainAdmin, "SafetyTrainingWorkerStats/tech2")));
    await assertFails(setDoc(doc(admin, "SafetyTrainingWorkerStats/tech"), { totalPoints: 1 }));
  });

  // ── Feedback ──
  const feedback = (extra = {}) => ({ sessionId: firstSessionId, workerUid: "tech", scenarioTitle: "Ladder",
    comment: "Good spot — also mention tie-off.", byUid: "plainadmin", byName: "Trainer", byRole: "Admin",
    createdAt: new Date(), ...extra });
  await t("trainer adds feedback on a worker's session", () =>
    assertSucceeds(addDoc(collection(plainAdmin, "SafetyTrainingFeedback"), feedback())));
  await t("feedback workerUid must match the session", () =>
    assertFails(addDoc(collection(plainAdmin, "SafetyTrainingFeedback"), feedback({ workerUid: "tech2" }))));
  await t("technician cannot write feedback", () =>
    assertFails(addDoc(collection(tech, "SafetyTrainingFeedback"), feedback({ byUid: "tech" }))));
  await t("worker reads only their own feedback", async () => {
    await assertSucceeds(getDocs(query(collection(tech, "SafetyTrainingFeedback"), where("workerUid", "==", "tech"))));
    await assertFails(getDocs(query(collection(tech2, "SafetyTrainingFeedback"), where("workerUid", "==", "tech"))));
  });

  // ── Notification triggers ──
  const queued = async (targetUid, type) => {
    let docs = [];
    await seed(async (db) => {
      docs = (await getDocs(query(collection(db, "UserNotificationQueue"), where("targetUid", "==", targetUid))))
        .docs.map((d) => d.data()).filter((d) => !type || d.payload.type === type);
    });
    return docs;
  };
  const runCreated = async (fn, path_, data) => {
    const { getFirestore } = require(require.resolve("firebase-admin/firestore", { paths: [path.join(ROOT, "functions")] }));
    const adminDb = getFirestore();
    const docRef = adminDb.doc(path_);
    await docRef.set(data);
    const snap = await docRef.get();
    await fn.run({ data: snap, params: { reviewId: docRef.id, feedbackId: docRef.id } });
  };
  await t("review trigger notifies worker and escalation recipient", async () => {
    await runCreated(fns.onSafetyTrainingReviewCreated, "SafetyTrainingReviews/esc1", {
      ...review({ status: "escalated", escalatedToUid: "admin2" }), expiresAt: null,
      reviewedAt: new Date(now) });
    const w = await queued("tech", "safety_training_review");
    const r = await queued("admin2", "safety_training_escalation");
    if (w.length < 1 || r.length !== 1) throw new Error(JSON.stringify({ w, r }));
  });
  await t("feedback trigger notifies the worker", async () => {
    await runCreated(fns.onSafetyTrainingFeedbackCreated, "SafetyTrainingFeedback/f1", feedback());
    const w = await queued("tech", "safety_training_feedback");
    if (w.length !== 1 || !w[0].body.includes("tie-off")) throw new Error(JSON.stringify(w));
  });

  // ── Daily follow-ups ──
  await t("daily follow-up: overdue retraining and expired clearance", async () => {
    await seed(async (db) => {
      await setDoc(doc(db, "UserRoles/late"), { role: "Technician" });
      await setDoc(doc(db, "UserRoles/lapsed"), { role: "Technician" });
      await setDoc(doc(db, "SafetyTrainingReviews/late1"), { workerUid: "late", workerName: "Late", status: "needsRetraining",
        assignedScenarioIds: ["s1", "s2", "inactive"], reviewedByUid: "admin", reviewedAt: Timestamp.fromMillis(now - 10 * DAY),
        dueAt: Timestamp.fromMillis(now - 2 * 60 * 60 * 1000) });
      await setDoc(doc(db, "SafetyTrainingReviews/lapsed1"), { workerUid: "lapsed", workerName: "Lapsed", status: "cleared",
        reviewedByUid: "admin", reviewedAt: Timestamp.fromMillis(now - 90 * DAY), expiresAt: Timestamp.fromMillis(now - 60 * 60 * 1000) });
    });
    // "late" did s1 after the review — only s2 remains (inactive is skipped).
    await call("late", { scenarioId: "s1", selectedOptionIndex: 2, reasoningAnswer: REASON, timeTakenSeconds: 5 });
    await fns.sendSafetyTrainingFollowUps.run({});
    const w = await queued("late", "safety_training_retraining_overdue");
    const rv = (await queued("admin", "safety_training_retraining_overdue")).filter((d) => d.body.includes("Late"));
    const lapsedW = await queued("lapsed", "safety_training_clearance_expired");
    if (w.length !== 1 || !w[0].body.startsWith("Your 1 retraining scenario") || rv.length !== 1 || lapsedW.length !== 1) {
      throw new Error(JSON.stringify({ w, rv, lapsedW }));
    }
  });

  // ── Storage media rules ──
  const adminSt = env.authenticatedContext("admin").storage();
  const techSt = env.authenticatedContext("tech").storage();
  const put = (st, name, bytes, contentType) => uploadBytes(ref(st, `SafetyTraining/Scenarios/s1/${name}`), bytes, { contentType });
  await t("storage: admin uploads a PNG scene photo", () => assertSucceeds(put(adminSt, "image.jpg", new Uint8Array(10), "image/png")));
  await t("storage: wrong content type rejected", () => assertFails(put(adminSt, "image.jpg", new Uint8Array(10), "application/pdf")));
  await t("storage: unexpected file name rejected", () => assertFails(put(adminSt, "evil.html", new Uint8Array(10), "text/html")));
  await t("storage: oversized Lottie rejected", () => assertFails(put(adminSt, "animation.json", new Uint8Array(5 * 1024 * 1024 + 1), "application/json")));
  await t("storage: technician cannot upload", () => assertFails(put(techSt, "animation.json", new Uint8Array(10), "application/json")));
  await t("storage: admin can delete replaced media", () => assertSucceeds(deleteObject(ref(adminSt, "SafetyTraining/Scenarios/s1/image.jpg"))));

  // ── Storage: project files, reports, attachments (catch-all path) ──
  const anonSt = env.unauthenticatedContext().storage();
  const clientSt = env.authenticatedContext("client").storage();
  const projectFile = "project1/Documents/123_spec.pdf";
  await t("storage: signed-in user uploads a project document", () =>
    assertSucceeds(uploadBytes(ref(clientSt, projectFile), new Uint8Array(10), { contentType: "application/pdf" })));
  await t("storage: signed-in user reads it back", () => assertSucceeds(getBytes(ref(techSt, projectFile))));
  await t("storage: signed-out visitor cannot read project files", () => assertFails(getBytes(ref(anonSt, projectFile))));
  await t("storage: signed-out visitor cannot upload", () =>
    assertFails(uploadBytes(ref(anonSt, "Reports/Daily/images/x.jpg"), new Uint8Array(10), { contentType: "image/jpeg" })));
  await t("storage: signed-out visitor cannot delete", () => assertFails(deleteObject(ref(anonSt, projectFile))));
  await t("storage: catch-all does not open Inventory to technicians' writes", () =>
    assertFails(uploadBytes(ref(techSt, "Inventory/Assets/a1/photo/x.jpg"), new Uint8Array(10), { contentType: "image/jpeg" })));

  await env.cleanup();
  console.log(`\n${passed} passed, ${failed} failed`);
  process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(1); });
