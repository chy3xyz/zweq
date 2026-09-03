import { describe, it, expect } from 'vitest';
import { formatDateTime } from '../format';

// `formatDateTime` renders local-time components; pin the timezone so the
// expected strings are deterministic regardless of the host's TZ.
process.env.TZ = 'UTC';

describe('formatDateTime', () => {
  it('returns "-" for falsy input', () => {
    expect(formatDateTime(0)).toBe('-');
  });

  it('formats a unix-seconds timestamp as YYYY-MM-DD HH:mm', () => {
    const ts = Date.UTC(2024, 0, 15, 8, 30, 45) / 1000;
    expect(formatDateTime(ts)).toBe('2024-01-15 08:30');
  });

  it('zero-pads month/day/hour/minute', () => {
    const ts = Date.UTC(2024, 2, 5, 9, 7, 0) / 1000;
    expect(formatDateTime(ts)).toBe('2024-03-05 09:07');
  });
});
