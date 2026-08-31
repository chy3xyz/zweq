export const PERMISSION_PATH = {
  roles: '/api/v1/roles',
  role: (id: number) => `/api/v1/roles/${id}`,
  rolePermissions: (id: number) => `/api/v1/roles/${id}/permissions`,
  permissions: '/api/v1/permissions',
  permission: (id: number) => `/api/v1/permissions/${id}`,
  userRoles: (userId: number) => `/api/v1/users/${userId}/roles`,
} as const;

export function roleListQuery(page: number, pageSize: number): string {
  return `${PERMISSION_PATH.roles}?page=${page}&page_size=${pageSize}`;
}

export function permissionListQuery(page: number, pageSize: number): string {
  return `${PERMISSION_PATH.permissions}?page=${page}&page_size=${pageSize}`;
}

export function unbindRolePermissionQuery(roleId: number, permissionId: number): string {
  return `${PERMISSION_PATH.rolePermissions(roleId)}?permission_id=${permissionId}`;
}
