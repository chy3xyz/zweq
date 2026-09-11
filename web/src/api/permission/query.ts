import { deleteEnvelope, getEnvelope, postEnvelope, putEnvelope } from '#ui/api/client';

import {
  PERMISSION_PATH,
  permissionListQuery,
  roleListQuery,
  unbindRolePermissionQuery,
} from './path';
import type {
  AssignRoleRequest,
  BindPermissionRequest,
  CreateRoleRequest,
  GrantPermissionRequest,
  PermissionItem,
  PermissionListResult,
  RoleItem,
  RoleListResult,
  UserRoleItem,
} from './types';

export async function listRoles(page: number, pageSize: number): Promise<RoleListResult> {
  return getEnvelope<RoleListResult>(roleListQuery(page, pageSize));
}

export async function createRole(body: CreateRoleRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(PERMISSION_PATH.roles, body);
}

export async function deleteRole(id: number): Promise<void> {
  await deleteEnvelope<null>(PERMISSION_PATH.role(id));
}

export async function listPermissions(page: number, pageSize: number): Promise<PermissionListResult> {
  return getEnvelope<PermissionListResult>(permissionListQuery(page, pageSize));
}

export async function grantPermission(body: GrantPermissionRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(PERMISSION_PATH.permissions, body);
}

export async function revokePermission(id: number): Promise<void> {
  await deleteEnvelope<null>(PERMISSION_PATH.permission(id));
}

export async function listRolePermissions(roleId: number): Promise<{ items: PermissionItem[] }> {
  return getEnvelope<{ items: PermissionItem[] }>(PERMISSION_PATH.rolePermissions(roleId));
}

export async function bindRolePermission(roleId: number, body: BindPermissionRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(PERMISSION_PATH.rolePermissions(roleId), body);
}

export async function unbindRolePermission(roleId: number, permissionId: number): Promise<void> {
  await deleteEnvelope<null>(unbindRolePermissionQuery(roleId, permissionId));
}

export async function listUserRoles(userId: number): Promise<{ items: UserRoleItem[] }> {
  return getEnvelope<{ items: UserRoleItem[] }>(PERMISSION_PATH.userRoles(userId));
}

export async function assignUserRole(userId: number, body: AssignRoleRequest): Promise<{ id: number }> {
  return putEnvelope<{ id: number }>(PERMISSION_PATH.userRoles(userId), body);
}

export type {
  AssignRoleRequest,
  BindPermissionRequest,
  CreateRoleRequest,
  GrantPermissionRequest,
  PermissionItem,
  PermissionListResult,
  RoleItem,
  RoleListResult,
  UserRoleItem,
};
