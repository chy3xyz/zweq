import { describe, it, expect } from 'vitest';
import { intParam } from '../query';

describe('intParam', () => {
  it('falls back for absent/empty values rather than coercing to 0', () => {
    expect(intParam(undefined, 5)).toBe(5);
    expect(intParam(null, 5)).toBe(5);
    expect(intParam('', 5)).toBe(5);
  });

  it('parses numeric strings, including "0" which is not falsy-empty', () => {
    expect(intParam('42', 5)).toBe(42);
    expect(intParam('0', 5)).toBe(0);
    expect(intParam('-7', 5)).toBe(-7);
  });

  it('keeps decimals as-is', () => {
    expect(intParam('3.5', 5)).toBe(3.5);
  });

  it('falls back on non-finite input', () => {
    expect(intParam('abc', 5)).toBe(5);
    expect(intParam('Infinity', 5)).toBe(5);
    expect(intParam('1e999', 5)).toBe(5); // -> Infinity
  });
});
