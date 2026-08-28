/** Check effective permission codes from /auth/me (admin/founder imply full access). */
export function hasPermission(permissions: string[] | undefined, required: string): boolean {
  if (!permissions?.length) return false;
  if (permissions.includes('admin') || permissions.includes('founder')) return true;
  return permissions.includes(required);
}

/** Admin-area navigation (most management pages). */
export function canAccessAdmin(permissions: string[] | undefined, adminFlag?: boolean): boolean {
  if (adminFlag) return true;
  return hasPermission(permissions, 'admin');
}
