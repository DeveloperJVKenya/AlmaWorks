// One-time migration script — NOT part of the Flutter app, NOT deployed
// anywhere. Run this locally, once, to create the missing UserRoles/{uid}
// mirror doc for every user who registered before that mirror existed.
//
// Why this needs the Admin SDK instead of the app itself:
// firestore.rules deliberately blocks all client-side UserRoles updates
// after initial signup-time creation (see the comment in firestore.rules),
// so an existing Admin/MainAdmin account has no way to create its own
// mirror doc through the app. The Admin SDK bypasses security rules
// entirely, which is exactly what a trusted, human-run, one-time migration
// is for.
//
// Setup:
//   1. Firebase Console -> Project Settings -> Service Accounts ->
//      "Generate new private key". Save the downloaded JSON as
//      serviceAccountKey.json in this same folder (scripts/backfill-user-roles/).
//      Do NOT commit that file — it grants full admin access to the project.
//   2. cd scripts/backfill-user-roles
//   3. npm install
//   4. npm run backfill
//      (add --dry-run as an extra arg to preview without writing:
//       node backfill.js --dry-run)
//
// The script is idempotent — safe to re-run; it skips any uid that already
// has a UserRoles doc unless --force is passed.

const path = require('path');
const admin = require('firebase-admin');

const args = process.argv.slice(2);
const dryRun = args.includes('--dry-run');
const force = args.includes('--force');

const serviceAccountPath = path.join(__dirname, 'serviceAccountKey.json');
let serviceAccount;
try {
  serviceAccount = require(serviceAccountPath);
} catch (e) {
  console.error(
    'Could not find serviceAccountKey.json in this folder.\n' +
    'Download it from Firebase Console -> Project Settings -> Service Accounts\n' +
    '-> Generate new private key, then save it as:\n  ' + serviceAccountPath
  );
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
const db = admin.firestore();

async function main() {
  console.log(`Backfill starting${dryRun ? ' (DRY RUN — no writes will be made)' : ''}...`);

  const usersSnap = await db.collection('Users').get();
  console.log(`Found ${usersSnap.size} Users document(s).`);

  let created = 0;
  let skippedExisting = 0;
  let skippedNoUid = 0;
  let skippedNoRole = 0;

  for (const doc of usersSnap.docs) {
    const data = doc.data();
    const uid = data.uid;
    const role = data.role;

    if (!uid) {
      console.warn(`  ⚠ Skipping Users/${doc.id} — no 'uid' field.`);
      skippedNoUid++;
      continue;
    }
    if (!role) {
      console.warn(`  ⚠ Skipping Users/${doc.id} (uid ${uid}) — no 'role' field.`);
      skippedNoRole++;
      continue;
    }

    const roleRef = db.collection('UserRoles').doc(uid);

    if (!force) {
      const existing = await roleRef.get();
      if (existing.exists) {
        skippedExisting++;
        continue;
      }
    }

    console.log(`  -> UserRoles/${uid} = { role: '${role}' }  (from Users/${doc.id})`);
    if (!dryRun) {
      await roleRef.set({ role });
    }
    created++;
  }

  console.log('\nDone.');
  console.log(`  Created/updated: ${created}`);
  console.log(`  Skipped (already had a UserRoles doc): ${skippedExisting}`);
  console.log(`  Skipped (missing uid field): ${skippedNoUid}`);
  console.log(`  Skipped (missing role field): ${skippedNoRole}`);
  if (dryRun) console.log('\nThis was a dry run — nothing was written. Re-run without --dry-run to apply.');
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error('Backfill failed:', err);
    process.exit(1);
  });
