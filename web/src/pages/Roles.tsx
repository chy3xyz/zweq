import { createSignal, For, Show, createEffect, onMount } from 'solid-js';

import {
  assignUserRole,
  bindRolePermission,
  createRole,
  deleteRole,
  grantPermission,
  listPermissions,
  listRolePermissions,
  listRoles,
  listUserRoles,
  permissionCode,
  revokePermission,
  toApiError,
  unbindRolePermission,
  type PermissionItem,
  type RoleItem,
} from '#ui/api';
import { useAuth } from '#ui/hooks';
import { hasPermission } from '#ui/utils/permissions';

type Tab = 'roles' | 'permissions' | 'bind' | 'users';

function Roles() {
  const [auth] = useAuth();
  const [tab, setTab] = createSignal<Tab>('roles');
  const [roles, setRoles] = createSignal<RoleItem[]>([]);
  const [permissions, setPermissions] = createSignal<PermissionItem[]>([]);
  const [selectedRoleId, setSelectedRoleId] = createSignal<number | null>(null);
  const [rolePerms, setRolePerms] = createSignal<PermissionItem[]>([]);
  const [userIdInput, setUserIdInput] = createSignal('');
  const [userRoleId, setUserRoleId] = createSignal<number | null>(null);
  const [loading, setLoading] = createSignal(false);
  const [error, setError] = createSignal('');

  const canWrite = () =>
    hasPermission(auth.user?.permissions, 'permission:write') || !!auth.user?.admin;

  const reload = async () => {
    setLoading(true);
    setError('');
    try {
      const [r, p] = await Promise.all([listRoles(1, 100), listPermissions(1, 200)]);
      setRoles(r.list);
      setPermissions(p.list);
      const sel = selectedRoleId();
      if (sel) {
        const bound = await listRolePermissions(sel);
        setRolePerms(bound.items);
      }
    } catch (err) {
      setError(toApiError(err).message);
    } finally {
      setLoading(false);
    }
  };

  onMount(() => void reload());

  createEffect(() => {
    const id = selectedRoleId();
    if (!id) {
      setRolePerms([]);
      return;
    }
    void listRolePermissions(id)
      .then((res) => setRolePerms(res.items))
      .catch((err) => setError(toApiError(err).message));
  });

  const onCreateRole = async () => {
    const name = window.prompt('角色名称');
    if (!name) return;
    const code = window.prompt('角色编码（founder/admin/operator）', 'operator');
    if (!code) return;
    try {
      await createRole({ name, code });
      await reload();
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onDeleteRole = async (role: RoleItem) => {
    if (!window.confirm(`删除角色「${role.name}」？`)) return;
    try {
      await deleteRole(role.id);
      if (selectedRoleId() === role.id) setSelectedRoleId(null);
      await reload();
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onGrantPermission = async () => {
    const module = window.prompt('模块名（如 shop）');
    if (!module) return;
    const action = window.prompt('动作（read 或 write）', 'read');
    if (!action) return;
    try {
      await grantPermission({ account_id: 0, module, action });
      await reload();
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onRevokePermission = async (perm: PermissionItem) => {
    if (!window.confirm(`撤销权限 ${permissionCode(perm)}？`)) return;
    try {
      await revokePermission(perm.id);
      await reload();
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const isBound = (permId: number) => rolePerms().some((p) => p.id === permId);

  const toggleBind = async (perm: PermissionItem) => {
    const roleId = selectedRoleId();
    if (!roleId) return;
    try {
      if (isBound(perm.id)) {
        await unbindRolePermission(roleId, perm.id);
      } else {
        await bindRolePermission(roleId, { permission_id: perm.id });
      }
      const bound = await listRolePermissions(roleId);
      setRolePerms(bound.items);
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onLoadUserRoles = async () => {
    const uid = Number(userIdInput());
    if (!uid) return;
    try {
      const res = await listUserRoles(uid);
      setUserRoleId(res.items[0]?.role_id ?? null);
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  const onAssignUserRole = async () => {
    const uid = Number(userIdInput());
    const rid = userRoleId();
    if (!uid || !rid) {
      window.alert('请填写用户 ID 并选择角色');
      return;
    }
    try {
      await assignUserRole(uid, { role_id: rid });
      window.alert('已绑定');
    } catch (err) {
      window.alert(toApiError(err).message);
    }
  };

  return (
    <div class="space-y-4">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 class="text-lg font-semibold">角色与权限</h2>
          <p class="text-sm text-base-content/60">管理 RBAC 角色、权限码与用户绑定</p>
        </div>
        <button type="button" class="btn btn-ghost btn-sm" onClick={() => void reload()} disabled={loading()}>
          刷新
        </button>
      </div>

      <Show when={error()}>
        <div class="alert alert-error text-sm">{error()}</div>
      </Show>

      <div class="tabs tabs-boxed w-fit">
        <button type="button" class={`tab ${tab() === 'roles' ? 'tab-active' : ''}`} onClick={() => setTab('roles')}>
          角色
        </button>
        <button type="button" class={`tab ${tab() === 'permissions' ? 'tab-active' : ''}`} onClick={() => setTab('permissions')}>
          权限码
        </button>
        <button type="button" class={`tab ${tab() === 'bind' ? 'tab-active' : ''}`} onClick={() => setTab('bind')}>
          角色授权
        </button>
        <button type="button" class={`tab ${tab() === 'users' ? 'tab-active' : ''}`} onClick={() => setTab('users')}>
          用户绑角色
        </button>
      </div>

      <Show when={tab() === 'roles'}>
        <div class="flex justify-end">
          <Show when={canWrite()}>
            <button type="button" class="btn btn-primary btn-sm" onClick={() => void onCreateRole()}>
              新建角色
            </button>
          </Show>
        </div>
        <div class="overflow-x-auto rounded-lg border border-base-300">
          <table class="table table-sm">
            <thead>
              <tr>
                <th>ID</th>
                <th>名称</th>
                <th>编码</th>
                <th>说明</th>
                <th />
              </tr>
            </thead>
            <tbody>
              <For each={roles()}>
                {(role) => (
                  <tr>
                    <td>{role.id}</td>
                    <td>{role.name}</td>
                    <td>
                      <span class="badge badge-outline badge-sm">{role.code}</span>
                    </td>
                    <td class="text-base-content/70">{role.description || '-'}</td>
                    <td>
                      <Show when={canWrite()}>
                        <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onDeleteRole(role)}>
                          删除
                        </button>
                      </Show>
                    </td>
                  </tr>
                )}
              </For>
            </tbody>
          </table>
        </div>
      </Show>

      <Show when={tab() === 'permissions'}>
        <div class="flex justify-end">
          <Show when={canWrite()}>
            <button type="button" class="btn btn-primary btn-sm" onClick={() => void onGrantPermission()}>
              新增权限码
            </button>
          </Show>
        </div>
        <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
          <For each={permissions()}>
            {(perm) => (
              <div class="flex items-center justify-between rounded-lg border border-base-300 px-3 py-2 text-sm">
                <code>{permissionCode(perm)}</code>
                <Show when={canWrite()}>
                  <button type="button" class="btn btn-ghost btn-xs text-error" onClick={() => void onRevokePermission(perm)}>
                    删
                  </button>
                </Show>
              </div>
            )}
          </For>
        </div>
      </Show>

      <Show when={tab() === 'bind'}>
        <div class="flex flex-wrap items-end gap-3">
          <label class="form-control w-full max-w-xs">
            <span class="label-text">选择角色</span>
            <select
              class="select select-bordered select-sm"
              value={selectedRoleId() ?? ''}
              onChange={(e) => setSelectedRoleId(e.currentTarget.value ? Number(e.currentTarget.value) : null)}
            >
              <option value="">请选择</option>
              <For each={roles()}>
                {(role) => <option value={role.id}>{role.name} ({role.code})</option>}
              </For>
            </select>
          </label>
        </div>
        <Show when={selectedRoleId()} fallback={<p class="text-sm text-base-content/50">先选择角色</p>}>
          <div class="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
            <For each={permissions()}>
              {(perm) => (
                <label class="flex cursor-pointer items-center gap-2 rounded-lg border border-base-300 px-3 py-2 text-sm">
                  <input
                    type="checkbox"
                    class="checkbox checkbox-sm"
                    checked={isBound(perm.id)}
                    disabled={!canWrite()}
                    onChange={() => void toggleBind(perm)}
                  />
                  <code>{permissionCode(perm)}</code>
                </label>
              )}
            </For>
          </div>
        </Show>
      </Show>

      <Show when={tab() === 'users'}>
        <div class="flex flex-wrap items-end gap-3">
          <label class="form-control">
            <span class="label-text">用户 ID</span>
            <input
              class="input input-bordered input-sm w-40"
              value={userIdInput()}
              onInput={(e) => setUserIdInput(e.currentTarget.value)}
            />
          </label>
          <button type="button" class="btn btn-ghost btn-sm" onClick={() => void onLoadUserRoles()}>
            查询当前角色
          </button>
          <label class="form-control">
            <span class="label-text">绑定角色</span>
            <select
              class="select select-bordered select-sm"
              value={userRoleId() ?? ''}
              onChange={(e) => setUserRoleId(e.currentTarget.value ? Number(e.currentTarget.value) : null)}
            >
              <option value="">请选择</option>
              <For each={roles()}>
                {(role) => <option value={role.id}>{role.name} ({role.code})</option>}
              </For>
            </select>
          </label>
          <Show when={canWrite()}>
            <button type="button" class="btn btn-primary btn-sm" onClick={() => void onAssignUserRole()}>
              保存绑定
            </button>
          </Show>
        </div>
        <p class="text-xs text-base-content/50">
          提示：操作员默认拥有全部 :read 权限；写操作需在「角色授权」中勾选对应 :write。
        </p>
      </Show>
    </div>
  );
}

export default Roles;
