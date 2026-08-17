'use strict';

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const admin = require('firebase-admin');
const { reconcileCreditCardAccount } = require('./lib/reconcile');

admin.initializeApp();

/**
 * On-demand balance-invariant safety net for credit cards, callable from
 * Settings ("Verify balances"). Recomputes each credit card's outstanding
 * balance server-side from the full transaction ledger and compares it to
 * the client-maintained running total. On a mismatch it never overwrites
 * the stored value — it only sets needsReconciliation so the client can
 * surface a "balance may be out of sync" prompt and let the user decide.
 *
 * Deliberately narrow: on-demand only (not a write-path trigger, not a
 * scheduled job), and scoped to credit cards only — see lib/reconcile.js
 * for why bank Account balances aren't included here. This is the one
 * Cloud Function this app has; justified specifically because the
 * credit-card-payment/purchase model added in this release means two
 * separate documents (the transaction and the card) must now agree with
 * each other, a risk that didn't exist when every transaction touched
 * exactly one account.
 */
exports.reconcileBalances = onCall(async (request) => {
  const uid = request.auth && request.auth.uid;
  if (!uid) {
    throw new HttpsError('unauthenticated', 'Sign in required.');
  }

  const db = admin.firestore();
  const userRef = db.collection('users').doc(uid);

  const cardsSnap = await userRef.collection('creditCardAccounts').get();

  const results = [];
  const batch = db.batch();
  let batchHasWrites = false;

  // Query per card rather than loading the entire transactions collection
  // into memory — that collection grows unbounded for an SMS-ingesting
  // ledger, while a card only ever needs the (typically small) subset of
  // transactions linked to it. An equality filter on creditCardAccountId
  // needs no composite index, and .select() limits each doc read to just
  // the two fields reconciliation actually uses.
  await Promise.all(
    cardsSnap.docs.map(async (cardDoc) => {
      const card = { id: cardDoc.id, ...cardDoc.data() };
      const linkedSnap = await userRef
        .collection('transactions')
        .where('creditCardAccountId', '==', card.id)
        .select('txnCategory', 'amount')
        .get();
      const linked = linkedSnap.docs.map((doc) => ({
        id: doc.id,
        creditCardAccountId: card.id,
        ...doc.data(),
      }));

      const result = reconcileCreditCardAccount(card, linked);
      results.push(result);

      const alreadyFlagged = card.needsReconciliation === true;
      if (!result.matches && !alreadyFlagged) {
        batch.update(cardDoc.ref, { needsReconciliation: true });
        batchHasWrites = true;
      } else if (result.matches && alreadyFlagged) {
        // Clear a stale flag once the numbers agree again — still never
        // touches the outstanding value itself, only the flag.
        batch.update(cardDoc.ref, { needsReconciliation: false });
        batchHasWrites = true;
      }
    }),
  );

  if (batchHasWrites) {
    await batch.commit();
  }

  return {
    checked: results.length,
    mismatched: results.filter((r) => !r.matches).length,
    results,
  };
});
