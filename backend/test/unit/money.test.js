const test = require('node:test');
const assert = require('node:assert/strict');
const { isValidAmount, parseAmount } = require('../../src/utils/money');

test('les montants FCFA doivent être des entiers positifs sûrs', () => {
  assert.equal(isValidAmount(1), true);
  assert.equal(isValidAmount(0), false);
  assert.equal(isValidAmount(-1), false);
  assert.equal(isValidAmount(1.5), false);
  assert.equal(parseAmount('150 000'), 150000);
  assert.equal(parseAmount('1.5'), null);
  assert.equal(parseAmount('999999999999999999999'), null);
});
