import { readFileSync } from 'node:fs';
import { after, before, beforeEach, describe, it } from 'node:test';

import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing';

let testEnv;

const PROJECT_ID = 'demo-ledger-rules-test';

function userDb(uid) {
  return testEnv.authenticatedContext(uid).firestore();
}

function unauthenticatedDb() {
  return testEnv.unauthenticatedContext().firestore();
}

async function seedProfile(uid, data = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context.firestore().doc(`users/${uid}`).set({
      name: uid,
      onboardingComplete: false,
      ...data,
    });
  });
}

async function seedTransaction(uid, transactionId, data = {}) {
  await testEnv.withSecurityRulesDisabled(async (context) => {
    await context
      .firestore()
      .doc(`users/${uid}/transactions/${transactionId}`)
      .set({
        title: 'Coffee',
        amount: 5,
        accountId: 'cash',
        ...data,
      });
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: readFileSync('firestore.rules', 'utf8'),
    },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv.cleanup();
});

describe('Firestore security rules', () => {
  it('allow signed-in users to manage only their own profile document', async () => {
    await seedProfile('alice');

    const alice = userDb('alice');
    const bob = userDb('bob');
    const anonymous = unauthenticatedDb();

    await assertSucceeds(alice.doc('users/alice').get());
    await assertSucceeds(
      alice.doc('users/alice').set({ onboardingComplete: true }, { merge: true }),
    );
    await assertSucceeds(alice.doc('users/alice').delete());

    await assertFails(anonymous.doc('users/alice').get());
    await assertFails(anonymous.doc('users/alice').set({ name: 'Anonymous' }));
    await assertFails(bob.doc('users/alice').get());
    await assertFails(
      bob.doc('users/alice').set({ onboardingComplete: true }, { merge: true }),
    );
    await assertFails(bob.doc('users/alice').delete());
  });

  it('allows first-time users to create their own profile during onboarding', async () => {
    const alice = userDb('alice');
    const anonymous = unauthenticatedDb();

    await assertSucceeds(
      alice.doc('users/alice').set({
        name: 'Alice',
        email: 'alice@example.com',
        onboardingComplete: false,
      }),
    );
    await assertFails(
      anonymous.doc('users/anonymous').set({
        name: 'Anonymous',
        onboardingComplete: false,
      }),
    );
  });

  it('keeps transaction subcollections private to the owning user', async () => {
    await seedTransaction('alice', 'tx-1');

    const alice = userDb('alice');
    const bob = userDb('bob');
    const anonymous = unauthenticatedDb();

    await assertSucceeds(alice.doc('users/alice/transactions/tx-1').get());
    await assertSucceeds(alice.collection('users/alice/transactions').get());
    await assertSucceeds(
      alice.doc('users/alice/transactions/tx-2').set({
        title: 'Salary',
        amount: 100,
        accountId: 'bank',
      }),
    );
    await assertSucceeds(
      alice.doc('users/alice/transactions/tx-1').update({ amount: 6 }),
    );
    await assertSucceeds(alice.doc('users/alice/transactions/tx-1').delete());

    await assertFails(anonymous.doc('users/alice/transactions/tx-1').get());
    await assertFails(bob.doc('users/alice/transactions/tx-1').get());
    await assertFails(bob.collection('users/alice/transactions').get());
    await assertFails(
      bob.doc('users/alice/transactions/tx-evil').set({
        title: 'Tampered',
        amount: 999,
        accountId: 'cash',
      }),
    );
    await assertFails(bob.doc('users/alice/transactions/tx-1').update({ amount: 1 }));
    await assertFails(bob.doc('users/alice/transactions/tx-1').delete());
  });

  it('does not expose documents outside the per-user data tree', async () => {
    await testEnv.withSecurityRulesDisabled(async (context) => {
      await context.firestore().doc('appConfig/defaults').set({ currency: 'INR' });
    });

    const alice = userDb('alice');

    await assertFails(alice.doc('appConfig/defaults').get());
    await assertFails(alice.doc('appConfig/defaults').set({ currency: 'USD' }));
  });
});
