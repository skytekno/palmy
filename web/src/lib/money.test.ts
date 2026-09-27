import { describe, expect, it } from 'vitest';
import { canonicalMoney, formatMoney, todayJakarta } from './money';

describe('exact money', () => {
  it.each([['1234.56', '1234.56'], ['9999999999999999.99', '9999999999999999.99'], ['00001.2', '1.20'], ['0.01', '0.01'], ['2000', '2000.00']])('preserves accepted precision %s', (input, expected) => {
    expect(canonicalMoney(input)).toBe(expected);
  });
  it.each(['0', '0.00', '-1', '+1', 'NaN', 'Infinity', '1e3', '1,234.56', '1.001', '.5', '1.', '10000000000000000', '', '１２３'])('rejects unsafe or ambiguous money %s', input => {
    expect(() => canonicalMoney(input)).toThrow();
  });
  it('formats signed totals without float truncation', () => {
    expect(formatMoney('9999999999999999.99')).toBe('Rp 9.999.999.999.999.999,99');
    expect(formatMoney('-1234.56')).toBe('−Rp 1.234,56');
    expect(formatMoney('0.00')).toBe('Rp 0,00');
  });
  it('returns a date-only Jakarta date', () => {
    expect(todayJakarta()).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });
});
