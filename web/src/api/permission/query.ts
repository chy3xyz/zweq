import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

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

async function get<T>(path: string): Promise<T> {
  const { data } = await http.get<{ code: number; msg: string; data: T }>(path);
  return unwrapEnvelope(data);
}

async function post<T>(path: string, body: unknown): Promise<T> {
  const { data } = await http.post<{ code: number; msg: string; data: T }>(path, body);
  return unwrapEnvelope(data);
}

async function put<T>(path: string, body: unknown): Promise<T> {
  const { data } = await http.put<{ code: number; msg: string; data: T }>(path, body);
  return unwrapEnvelope(data);
}

async function del<T>(path: string): Promise<T> {
  const { data } = await http.delete<{ code: number; msg: string; data: T }>(path);
  return unwrapEnvelope(data);
}

export async function listRoles(page: number, pageSize: number): Promise<RoleListResult> {
  return get<RoleListResult>(roleListQuery(page, pageSize));
}

export async function createRole(body: CreateRoleRequest): Promise<{ id: number }> {
  return post<{ id: number }>(PERMISSION_PATH.roles, body);
}

export async function deleteRole(id: number): Promise<void> {
  await del<null>(PERMISSION_PATH.role(id));
}

export async function listPermissions(page: number, pageSize: number): Promise<PermissionListResult> {
  return get<PermissionListResult>(permissionListQuery(page, pageSize));
}

export async function grantPermission(body: GrantPermissionRequest): Promise<{ id: number }> {
  return post<{ id: number }>(PERMISSION_PATH.permissions, body);
}

export async function revokePermission(id: number): Promise<void> {
  await del<null>(PERMISSION_PATH.permission(id));
}

export async function listRolePermissions(roleId: number): Promise<{ items: PermissionItem[] }> {
  return get<{ items: PermissionItem[] }>(PERMISSION_PATH.rolePermissions(roleId));
}

export async function bindRolePermission(roleId: number, body: BindPermissionRequest): Promise<{ id: number }> {
  return post<{ id: number }>(PERMISSION_PATH.rolePermissions(roleId), body);
}

export async function unbindRolePermission(roleId: number, permissionId: number): Promise<void> {
  await del<null>(unbindRolePermissionQuery(roleId, permissionId));
}

export async function listUserRoles(userId: number): Promise<{ items: UserRoleItem[] }> {
  return get<{ items: UserRoleItem[] }>(PERMISSION_PATH.userRoles(userId));
}

export async function assignUserRole(userId: number, body: AssignRoleRequest): Promise<{ id: number }> {
  return put<{ id: number }>(PERMISSION_PATH.userRoles(userId), body);
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
