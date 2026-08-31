import { createEffect, createSignal, Show } from 'solid-js';

import { type AuthUser, createUser, updateUser } from '#ui/api';
import FormField from '#ui/components/FormField';
import FormModal from '#ui/components/FormModal';

export type UserFormTarget = 'create' | 'edit';

interface Props {
  open: boolean;
  mode: UserFormTarget;
  user: AuthUser | null;
  onClose: () => void;
  onSaved: () => void;
}

function UserFormModal(props: Props) {
  const [name, setName] = createSignal('');
  const [email, setEmail] = createSignal('');
  const [password, setPassword] = createSignal('');
  const [admin, setAdmin] = createSignal(false);
  const [verified, setVerified] = createSignal(false);
  const [tenantId, setTenantId] = createSignal(1);
  const [submitting, setSubmitting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  createEffect(() => {
    if (props.open) {
      setError(null);
      setName(props.user?.name ?? '');
      setEmail(props.user?.email ?? '');
      setPassword('');
      setAdmin(props.user?.admin ?? false);
      setVerified(props.user?.verified ?? false);
      setTenantId(props.user?.tenant_id ?? 1);
    }
  });

  const onSubmit = async () => {
    if (submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      if (props.mode === 'create') {
        await createUser({
          name: name().trim(),
          email: email().trim(),
          password: password(),
          admin: admin(),
          tenant_id: tenantId(),
        });
      } else if (props.user) {
        await updateUser(props.user.id, {
          name: name().trim(),
          email: email().trim(),
          admin: admin(),
          verified: verified(),
        });
      }
      props.onSaved();
      props.onClose();
    } catch (err) {
      setError(err instanceof Error ? err.message : '保存失败，请稍后重试');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <FormModal
      open={props.open}
      title={props.mode === 'create' ? '新建用户' : `编辑用户 #${props.user?.id ?? ''}`}
      description={props.mode === 'create' ? '创建后用户需通过邮箱验证登录' : undefined}
      onSubmit={onSubmit}
      onClose={props.onClose}
      submitting={submitting()}
      error={error()}
      submitLabel="保存"
    >
      <FormField label="姓名" required>
        <input
          type="text"
          class="input input-bordered input-sm w-full"
          value={name()}
          onInput={(e) => setName(e.currentTarget.value)}
          placeholder="用户姓名"
        />
      </FormField>
      <FormField label="邮箱" required>
        <input
          type="email"
          class="input input-bordered input-sm w-full"
          value={email()}
          onInput={(e) => setEmail(e.currentTarget.value)}
          placeholder="name@example.com"
        />
      </FormField>
      <Show when={props.mode === 'create'}>
        <FormField label="初始密码" required hint="至少 8 位，建议字母 + 数字组合">
          <input
            type="password"
            class="input input-bordered input-sm w-full"
            placeholder="••••••••"
            value={password()}
            onInput={(e) => setPassword(e.currentTarget.value)}
            minlength={8}
          />
        </FormField>
        <FormField label="租户" required hint="用户数据归属的租户 ID">
          <input
            type="number"
            class="input input-bordered input-sm w-full"
            value={tenantId()}
            onInput={(e) => setTenantId(Number(e.currentTarget.value) || 1)}
            min={1}
          />
        </FormField>
      </Show>
      <div class="flex gap-8 pt-1">
        <label class="flex cursor-pointer items-center gap-2">
          <input
            type="checkbox"
            class="toggle toggle-sm"
            checked={admin()}
            onChange={(e) => setAdmin(e.currentTarget.checked)}
          />
          <span class="text-sm">管理员</span>
        </label>
        <Show when={props.mode === 'edit'}>
          <label class="flex cursor-pointer items-center gap-2">
            <input
              type="checkbox"
              class="toggle toggle-sm"
              checked={verified()}
              onChange={(e) => setVerified(e.currentTarget.checked)}
            />
            <span class="text-sm">已验证</span>
          </label>
        </Show>
      </div>
    </FormModal>
  );
}

export default UserFormModal;
