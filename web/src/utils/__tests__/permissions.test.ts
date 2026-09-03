import { describe, it, expect } from 'vitest';
import { hasPermission, canAccessAdmin, canAccessNav } from '../permissions';

describe('hasPermission', () => {
  it('denies when permissions is empty or undefined', () => {
    expect(hasPermission(undefined, 'a:read')).toBe(false);
    expect(hasPermission([], 'a:read')).toBe(false);
  });

  it('allows admin/founder for any required code', () => {
    expect(hasPermission(['admin'], 'anything:write')).toBe(true);
    expect(hasPermission(['founder'], 'anything:write')).toBe(true);
  });

  it('allows an explicitly granted code', () => {
    expect(hasPermission(['a:read'], 'a:read')).toBe(true);
  });

  it('implies read from write (":write" grants ":read")', () => {
    expect(hasPermission(['a:write'], 'a:read')).toBe(true);
  });

  it('does not imply write from read', () => {
    expect(hasPermission(['a:read'], 'a:write')).toBe(false);
  });

  it('denies unrelated codes', () => {
    expect(hasPermission(['b:read'], 'a:read')).toBe(false);
    expect(hasPermission(['a:write'], 'a:create')).toBe(false);
  });
});

describe('canAccessAdmin', () => {
  it('returns true when adminFlag is set', () => {
    expect(canAccessAdmin(undefined, true)).toBe(true);
  });

  it('falls back to hasPermission(admin)', () => {
    expect(canAccessAdmin(['admin'], false)).toBe(true);
    expect(canAccessAdmin(['user'], false)).toBe(false);
  });
});

describe('canAccessNav', () => {
  it('returns true when adminFlag is set', () => {
    expect(canAccessNav(['user:read'], true, 'user:write')).toBe(true);
  });

  it('falls back to hasPermission(required)', () => {
    expect(canAccessNav(['ord:list'], false, 'ord:list')).toBe(true);
    expect(canAccessNav(['ord:list'], false, 'ord:create')).toBe(false);
  });
});
