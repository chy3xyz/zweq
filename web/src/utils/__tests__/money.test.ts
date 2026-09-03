import { describe, it, expect } from 'vitest';
import { fenToYuan, yuanToFen, formatYuan } from '../money';

describe('fenToYuan', () => {
  it('converts cents into a 2-decimal yuan string', () => {
    expect(fenToYuan(1250)).toBe('12.50');
    expect(fenToYuan(5)).toBe('0.05');
    expect(fenToYuan(0)).toBe('0.00');
  });

  it('handles negative amounts', () => {
    expect(fenToYuan(-1234)).toBe('-12.34');
    expect(fenToYuan(-5)).toBe('-0.05');
  });
});

describe('yuanToFen', () => {
  it('rounds yuan to the nearest cent', () => {
    expect(yuanToFen(12.5)).toBe(1250);
    expect(yuanToFen(0.1)).toBe(10);
    expect(yuanToFen(0)).toBe(0);
  });

  it('rounds away floating-point drift', () => {
    // 0.29 * 100 === 28.999... in float; Math.round recovers the integer cent.
    expect(yuanToFen(0.29)).toBe(29);
  });
});

describe('formatYuan', () => {
  it('prepends the ¥ symbol', () => {
    expect(formatYuan(1250)).toBe('¥12.50');
    expect(formatYuan(0)).toBe('¥0.00');
  });
});
