import { createSignal, Show } from 'solid-js';

import { changePassword, toApiError } from '#ui/api';
import BaseModal from '#ui/components/BaseModal';

interface Props {
  open: boolean;
  onClose: () => void;
}

function ChangePasswordModal(props: Props) {
  const [oldPassword, setOldPassword] = createSignal('');
  const [newPassword, setNewPassword] = createSignal('');
  const [confirm, setConfirm] = createSignal('');
  const [error, setError] = createSignal<string | null>(null);
  const [saving, setSaving] = createSignal(false);

  const onSubmit = async (e: SubmitEvent) => {
    e.preventDefault();
    if (saving()) return;
    if (newPassword() !== confirm()) {
      setError('两次输入的新密码不一致');
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await changePassword({ old_password: oldPassword(), new_password: newPassword() });
      setOldPassword('');
      setNewPassword('');
      setConfirm('');
      props.onClose();
      window.alert('密码已更新');
    } catch (err) {
      setError(toApiError(err).message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <BaseModal open={props.open} title="修改密码" onClose={props.onClose} size="sm">
      <Show when={error()}>
        <div role="alert" class="alert alert-error mb-3 py-2 text-sm">
          {error()}
        </div>
      </Show>
      <form onSubmit={onSubmit} class="space-y-3">
        <label class="form-control w-full">
          <span class="label-text mb-1">当前密码</span>
          <input
            type="password"
            class="input input-bordered w-full"
            value={oldPassword()}
            onInput={(e) => setOldPassword(e.currentTarget.value)}
            required
          />
        </label>
        <label class="form-control w-full">
          <span class="label-text mb-1">新密码</span>
          <input
            type="password"
            class="input input-bordered w-full"
            value={newPassword()}
            onInput={(e) => setNewPassword(e.currentTarget.value)}
            minlength={8}
            required
          />
        </label>
        <label class="form-control w-full">
          <span class="label-text mb-1">确认新密码</span>
          <input
            type="password"
            class="input input-bordered w-full"
            value={confirm()}
            onInput={(e) => setConfirm(e.currentTarget.value)}
            minlength={8}
            required
          />
        </label>
        <div class="flex justify-end gap-2 pt-2">
          <button type="button" class="btn" onClick={props.onClose}>
            取消
          </button>
          <button type="submit" class="btn btn-primary" disabled={saving()}>
            {saving() ? '保存中…' : '保存'}
          </button>
        </div>
      </form>
    </BaseModal>
  );
}

export default ChangePasswordModal;
