/** Check effective permission codes from /auth/me (admin/founder imply full access). */
export function hasPermission(permissions: string[] | undefined, required: string): boolean {
  if (!permissions?.length) return false;
  if (permissions.includes('admin') || permissions.includes('founder')) return true;
  if (permissions.includes(required)) return true;
  // write 隐含 read
  if (required.endsWith(':read')) {
    const write = `${required.slice(0, -':read'.length)}:write`;
    if (permissions.includes(write)) return true;
  }
  return false;
}

/** Admin-area navigation (most management pages). */
export function canAccessAdmin(permissions: string[] | undefined, adminFlag?: boolean): boolean {
  if (adminFlag) return true;
  return hasPermission(permissions, 'admin');
}

export function canAccessNav(
  permissions: string[] | undefined,
  adminFlag: boolean | undefined,
  required: string,
): boolean {
  if (adminFlag) return true;
  return hasPermission(permissions, required);
}
