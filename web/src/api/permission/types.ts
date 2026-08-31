export interface RoleItem {
  id: number;
  tenant_id: number;
  name: string;
  code: string;
  description: string;
  created_at: number;
  updated_at: number;
}

export interface PermissionItem {
  id: number;
  tenant_id: number;
  account_id: number;
  module: string;
  action: string;
  created_at: number;
  updated_at: number;
}

export interface RoleListResult {
  list: RoleItem[];
  total: number;
}

export interface PermissionListResult {
  list: PermissionItem[];
  total: number;
}

export interface CreateRoleRequest {
  name: string;
  code: string;
  description?: string;
}

export interface GrantPermissionRequest {
  account_id: number;
  module: string;
  action: string;
}

export interface BindPermissionRequest {
  permission_id: number;
}

export interface AssignRoleRequest {
  role_id: number;
}

export interface UserRoleItem {
  user_id: number;
  role_id: number;
}

export function permissionCode(item: PermissionItem): string {
  return `${item.module}:${item.action}`;
}
