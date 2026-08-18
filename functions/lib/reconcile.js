'use strict';

/**
 * Pure reconciliation logic, kept separate from the Cloud Functions/
 * firebase-admin wrapper (index.js) so it can be unit tested with plain
 * `node --test`, no emulator required.
 *
 * Scoped to credit card accounts only, not bank Accounts. A credit card's
 * currentOutstanding has a well-defined zero anchor (every CreditCardAccount
 * is created with currentOutstanding: 0 — see
 * CreditCardDetailsBottomSheet/createCreditCardAccount), so "recompute from
 * the full transaction ledger" is sound. A bank Account's balance has no
 * equivalent anchor — its initial value is whatever the user entered as
 * their real-world starting balance, not tracked as a separate
 * openingBalance field — so a from-scratch ledger reconstruction can't be
 * validated without a larger schema addition. That's left as a documented
 * follow-up rather than bundled into this release.
 */

const RECONCILE_TOLERANCE = 0.01;

function computeCreditCardOutstanding(linkedTransactions) {
  let outstanding = 0;
  for (const tx of linkedTransactions) {
    if (tx.txnCategory === 'creditCardPurchase') {
      outstanding += tx.amount || 0;
    } else if (
      tx.txnCategory === 'creditCardPayment' ||
      // A refund credited back to a card lowers its outstanding by the
      // same sign as a payment — see add_transaction_screen.dart's
      // newCardDelta/oldCardDelta, which applies -amount for both
      // categories. Omitting refund here made reconcileBalances flag a
      // false mismatch on every card with a refund transaction.
      tx.txnCategory === 'refund'
    ) {
      outstanding -= tx.amount || 0;
    }
  }
  return outstanding;
}

/**
 * @param {{id: string, currentOutstanding?: number}} card
 * @param {Array<{id: string, creditCardAccountId?: string, txnCategory?: string, amount?: number}>} allTransactions
 */
function reconcileCreditCardAccount(card, allTransactions) {
  const linked = allTransactions.filter(
    (tx) => tx.creditCardAccountId === card.id,
  );
  const computedOutstanding = computeCreditCardOutstanding(linked);
  const storedOutstanding = card.currentOutstanding || 0;
  const matches =
    Math.abs(computedOutstanding - storedOutstanding) < RECONCILE_TOLERANCE;

  return {
    cardId: card.id,
    computedOutstanding,
    storedOutstanding,
    matches,
    transactionCount: linked.length,
  };
}

module.exports = {
  RECONCILE_TOLERANCE,
  computeCreditCardOutstanding,
  reconcileCreditCardAccount,
};
