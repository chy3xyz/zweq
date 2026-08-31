import { createEffect, createSignal, Show } from 'solid-js';

import {
  createAccount,
  getWechatConfig,
  setWechatConfig,
  toApiError,
  type AccountItem,
  type AccountKind,
} from '#ui/api';
import BaseModal from '#ui/components/BaseModal';

interface Props {
  open: boolean;
  onClose: () => void;
  onSaved: () => void;
}

function AccountCreateModal(props: Props) {
  const [name, setName] = createSignal('');
  const [kind, setKind] = createSignal<AccountKind>('wechat');
  const [submitting, setSubmitting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  createEffect(() => {
    if (props.open) {
      setName('');
      setKind('wechat');
      setError(null);
    }
  });

  const onSubmit = async (e: SubmitEvent) => {
    e.preventDefault();
    if (submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      await createAccount({ name: name().trim(), kind: kind() });
      props.onSaved();
      props.onClose();
    } catch (err) {
      setError(toApiError(err).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <BaseModal open={props.open} title="新增账号" onClose={props.onClose}>
      <Show when={error()}>
        <div role="alert" class="alert alert-error mb-3 py-2 text-sm">
          {error()}
        </div>
      </Show>
      <form onSubmit={onSubmit} class="space-y-3">
        <label class="form-control w-full">
          <span class="label-text mb-1">账号名称</span>
          <input
            type="text"
            class="input input-bordered w-full"
            placeholder="例如：我的公众号"
            value={name()}
            onInput={(e) => setName(e.currentTarget.value)}
            required
          />
        </label>
        <label class="form-control w-full">
          <span class="label-text mb-1">类型</span>
          <select
            class="select select-bordered w-full"
            value={kind()}
            onChange={(e) => setKind(e.currentTarget.value as AccountKind)}
          >
            <option value="wechat">公众号</option>
            <option value="wxapp">小程序</option>
            <option value="app">APP</option>
          </select>
        </label>
        <div class="flex justify-end gap-2 pt-2">
          <button type="button" class="btn" onClick={props.onClose}>
            取消
          </button>
          <button type="submit" class="btn btn-primary" disabled={submitting()}>
            {submitting() ? '创建中…' : '创建'}
          </button>
        </div>
      </form>
    </BaseModal>
  );
}

interface WechatProps extends Props {
  account: AccountItem | null;
}

export function AccountWechatModal(props: WechatProps) {
  const [appid, setAppid] = createSignal('');
  const [token, setToken] = createSignal('');
  const [secret, setSecret] = createSignal('');
  const [submitting, setSubmitting] = createSignal(false);
  const [error, setError] = createSignal<string | null>(null);

  createEffect(() => {
    if (!props.open || !props.account) return;
    setError(null);
    setAppid('');
    setToken('');
    setSecret('');
    void (async () => {
      try {
        const cfg = await getWechatConfig(props.account!.id);
        if (cfg) {
          setAppid(cfg.appid);
          setToken(cfg.token);
        }
      } catch {
        // ignore
      }
    })();
  });

  const onSubmit = async (e: SubmitEvent) => {
    e.preventDefault();
    const account = props.account;
    if (!account || submitting()) return;
    setSubmitting(true);
    setError(null);
    try {
      await setWechatConfig(account.id, {
        appid: appid().trim(),
        token: token().trim(),
        secret: secret().trim() || undefined,
      });
      props.onSaved();
      props.onClose();
    } catch (err) {
      setError(toApiError(err).message);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <BaseModal
      open={props.open}
      title={`微信配置 — ${props.account?.name ?? ''}`}
      onClose={props.onClose}
      size="lg"
    >
      <Show when={error()}>
        <div role="alert" class="alert alert-error mb-3 py-2 text-sm">
          {error()}
        </div>
      </Show>
      <form onSubmit={onSubmit} class="grid grid-cols-1 gap-3 md:grid-cols-2">
        <label class="form-control">
          <span class="label-text mb-1">AppID</span>
          <input
            type="text"
            class="input input-bordered"
            value={appid()}
            onInput={(e) => setAppid(e.currentTarget.value)}
            required
          />
        </label>
        <label class="form-control">
          <span class="label-text mb-1">Token</span>
          <input
            type="text"
            class="input input-bordered"
            value={token()}
            onInput={(e) => setToken(e.currentTarget.value)}
            required
          />
        </label>
        <label class="form-control md:col-span-2">
          <span class="label-text mb-1">AppSecret（留空保持不变）</span>
          <input
            type="password"
            class="input input-bordered"
            value={secret()}
            onInput={(e) => setSecret(e.currentTarget.value)}
          />
        </label>
        <div class="flex justify-end gap-2 md:col-span-2">
          <button type="button" class="btn" onClick={props.onClose}>
            取消
          </button>
          <button type="submit" class="btn btn-primary" disabled={submitting()}>
            {submitting() ? '保存中…' : '保存'}
          </button>
        </div>
      </form>
    </BaseModal>
  );
}

export default AccountCreateModal;
