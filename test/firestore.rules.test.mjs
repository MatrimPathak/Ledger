import { after, afterEach, before, test } from 'node:test';
import { readFile } from 'node:fs/promises';
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'demo-ledger-rules',
    firestore: {
      rules: await readFile('firestore.rules', 'utf8'),
    },
  });
});

afterEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv.cleanup();
});

test('authenticated users can manage their own profile document', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();
  const profileRef = db.doc('users/alice');

  await assertSucceeds(profileRef.set({ displayName: 'Alice' }));
  await assertSucceeds(profileRef.get());
  await assertSucceeds(profileRef.update({ currency: 'USD' }));
  await assertSucceeds(profileRef.delete());
});

test('authenticated users can manage documents in their own user subcollections', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();
  const accountRef = db.doc('users/alice/accounts/checking');

  await assertSucceeds(accountRef.set({ name: 'Checking', balance: 100 }));
  await assertSucceeds(accountRef.get());
  await assertSucceeds(db.collection('users/alice/accounts').get());
  await assertSucceeds(accountRef.update({ balance: 125 }));
  await assertSucceeds(accountRef.delete());
});

test('unauthenticated clients cannot access user data', async () => {
  const db = testEnv.unauthenticatedContext().firestore();

  await assertFails(db.doc('users/alice').get());
  await assertFails(db.doc('users/alice').set({ displayName: 'Alice' }));
  await assertFails(db.doc('users/alice/accounts/checking').get());
  await assertFails(
    db.doc('users/alice/accounts/checking').set({
      name: 'Checking',
      balance: 100,
    }),
  );
});

test('authenticated users cannot access another user document or subcollection', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();

  await assertFails(db.doc('users/bob').get());
  await assertFails(db.doc('users/bob').set({ displayName: 'Bob' }));
  await assertFails(db.doc('users/bob/accounts/checking').get());
  await assertFails(
    db.doc('users/bob/accounts/checking').set({
      name: 'Checking',
      balance: 100,
    }),
  );
});

test('authenticated users cannot enumerate all user documents', async () => {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().doc('users/alice').set({ displayName: 'Alice' });
    await context.firestore().doc('users/bob').set({ displayName: 'Bob' });
  });

  const db = testEnv.authenticatedContext('alice').firestore();

  await assertFails(db.collection('users').get());
});

test('documents outside user-owned paths are denied', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();

  await assertFails(db.doc('public/config').get());
  await assertFails(db.doc('public/config').set({ enabled: true }));
});
