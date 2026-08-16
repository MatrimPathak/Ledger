'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const {
  computeCreditCardOutstanding,
  reconcileCreditCardAccount,
} = require('../lib/reconcile');

test('computeCreditCardOutstanding sums purchases and subtracts payments', () => {
  const outstanding = computeCreditCardOutstanding([
    { txnCategory: 'creditCardPurchase', amount: 1500 },
    { txnCategory: 'creditCardPurchase', amount: 2000 },
    { txnCategory: 'creditCardPayment', amount: 3500 },
  ]);

  assert.equal(outstanding, 0);
});

test('computeCreditCardOutstanding ignores unrelated transaction categories', () => {
  const outstanding = computeCreditCardOutstanding([
    { txnCategory: 'creditCardPurchase', amount: 1000 },
    { txnCategory: 'expense', amount: 500 },
    { txnCategory: 'refund', amount: 200 },
  ]);

  assert.equal(outstanding, 1000);
});

test('reconcileCreditCardAccount matches when the stored value agrees', () => {
  const card = { id: 'card-1', currentOutstanding: 4000 };
  const transactions = [
    { creditCardAccountId: 'card-1', txnCategory: 'creditCardPurchase', amount: 1500 },
    { creditCardAccountId: 'card-1', txnCategory: 'creditCardPurchase', amount: 2500 },
    // A different card's transaction must not be counted.
    { creditCardAccountId: 'card-2', txnCategory: 'creditCardPurchase', amount: 9999 },
  ];

  const result = reconcileCreditCardAccount(card, transactions);

  assert.equal(result.matches, true);
  assert.equal(result.computedOutstanding, 4000);
  assert.equal(result.storedOutstanding, 4000);
  assert.equal(result.transactionCount, 2);
});

test('reconcileCreditCardAccount flags a mismatch without altering the stored value', () => {
  const card = { id: 'card-1', currentOutstanding: 5000 };
  const transactions = [
    { creditCardAccountId: 'card-1', txnCategory: 'creditCardPurchase', amount: 1500 },
  ];

  const result = reconcileCreditCardAccount(card, transactions);

  assert.equal(result.matches, false);
  assert.equal(result.computedOutstanding, 1500);
  assert.equal(result.storedOutstanding, 5000);
});

test('reconcileCreditCardAccount tolerates sub-cent floating point drift', () => {
  const card = { id: 'card-1', currentOutstanding: 0.1 + 0.2 };
  const transactions = [
    { creditCardAccountId: 'card-1', txnCategory: 'creditCardPurchase', amount: 0.3 },
  ];

  const result = reconcileCreditCardAccount(card, transactions);

  assert.equal(result.matches, true);
});

test('reconcileCreditCardAccount treats a card with no linked transactions as zero',
  () => {
    const card = { id: 'card-1', currentOutstanding: 0 };

    const result = reconcileCreditCardAccount(card, []);

    assert.equal(result.matches, true);
    assert.equal(result.transactionCount, 0);
  });
