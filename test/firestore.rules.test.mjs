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

test('transaction writes require a non-negative numeric amount matching the owner', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();
  const txRef = db.doc('users/alice/transactions/tx-1');

  await assertSucceeds(
    txRef.set({ userId: 'alice', amount: 250, title: 'Coffee' }),
  );
  await assertFails(
    db.doc('users/alice/transactions/tx-bad-amount').set({
      userId: 'alice',
      amount: -50,
      title: 'Refund abuse',
    }),
  );
  await assertFails(
    db.doc('users/alice/transactions/tx-bad-owner').set({
      userId: 'bob',
      amount: 50,
      title: 'Spoofed owner',
    }),
  );
  await assertFails(
    db.doc('users/alice/transactions/tx-non-numeric').set({
      userId: 'alice',
      amount: '50',
      title: 'Non-numeric amount',
    }),
  );
});

test('transaction writes validate txnCategory and processingStatus enums when present', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();

  await assertSucceeds(
    db.doc('users/alice/transactions/tx-valid-enum').set({
      userId: 'alice',
      amount: 100,
      txnCategory: 'creditCardPayment',
      processingStatus: 'confirmed',
    }),
  );
  await assertFails(
    db.doc('users/alice/transactions/tx-bad-category').set({
      userId: 'alice',
      amount: 100,
      txnCategory: 'notARealCategory',
    }),
  );
  await assertFails(
    db.doc('users/alice/transactions/tx-bad-status').set({
      userId: 'alice',
      amount: 100,
      processingStatus: 'madeUpStatus',
    }),
  );
});

test('non-transaction subcollections keep the original unconditional owner-write behavior', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();

  // No userId/amount fields at all — must still succeed, since validation
  // is scoped to the transactions subcollection only.
  await assertSucceeds(
    db.doc('users/alice/merchants/uber').set({ displayName: 'Uber' }),
  );
});

test('credit card account writes require the owner and numeric outstanding/limit', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();

  await assertSucceeds(
    db.doc('users/alice/creditCardAccounts/card-1').set({
      userId: 'alice',
      title: 'HDFC Regalia',
      currentOutstanding: 18450,
      creditLimit: 100000,
    }),
  );
  await assertFails(
    db.doc('users/alice/creditCardAccounts/card-bad-owner').set({
      userId: 'bob',
      currentOutstanding: 0,
    }),
  );
  await assertFails(
    db.doc('users/alice/creditCardAccounts/card-non-numeric').set({
      userId: 'alice',
      currentOutstanding: '18450',
    }),
  );
});

test('subscription writes require the owner and a known kind/status/numeric amount', async () => {
  const db = testEnv.authenticatedContext('alice').firestore();

  await assertSucceeds(
    db.doc('users/alice/subscriptions/sub-1').set({
      userId: 'alice',
      merchantNameRaw: 'Netflix',
      kind: 'subscription',
      expectedAmount: 649,
      status: 'active',
    }),
  );
  await assertFails(
    db.doc('users/alice/subscriptions/sub-bad-owner').set({
      userId: 'bob',
      kind: 'subscription',
      expectedAmount: 649,
    }),
  );
  await assertFails(
    db.doc('users/alice/subscriptions/sub-bad-kind').set({
      userId: 'alice',
      kind: 'notARealKind',
      expectedAmount: 649,
    }),
  );
  await assertFails(
    db.doc('users/alice/subscriptions/sub-non-numeric').set({
      userId: 'alice',
      kind: 'subscription',
      expectedAmount: '649',
    }),
  );
  await assertFails(
    db.doc('users/alice/subscriptions/sub-bad-status').set({
      userId: 'alice',
      kind: 'subscription',
      expectedAmount: 649,
      status: 'madeUpStatus',
    }),
  );
});
