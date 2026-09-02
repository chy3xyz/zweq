import { Show, createEffect, createSignal } from 'solid-js';

import type { WechatMenuButton } from '#ui/api';

import FormField from './FormField';
import FormModal from './FormModal';

const TYPE_OPTIONS: { value: WechatMenuButton['type']; label: string }[] = [
  { value: 'click', label: '点击推事件 (click)' },
  { value: 'view', label: '跳转 URL (view)' },
  { value: 'miniprogram', label: '小程序 (miniprogram)' },
  { value: 'media_id', label: '下发消息 (media_id)' },
];

interface Props {
  open: boolean;
  mode: 'create' | 'edit';
  parentName?: string;
  initial?: WechatMenuButton;
  onSave: (button: WechatMenuButton) => void;
  onClose: () => void;
}

export default function MenuButtonFormModal(props: Props) {
  const [name, setName] = createSignal('');
  const [type, setType] = createSignal<WechatMenuButton['type']>('click');
  const [key, setKey] = createSignal('');
  const [url, setUrl] = createSignal('');
  const [mediaId, setMediaId] = createSignal('');
  const [appid, setAppid] = createSignal('');
  const [pagepath, setPagepath] = createSignal('');
  const [error, setError] = createSignal<string | null>(null);
  const [submitting, setSubmitting] = createSignal(false);

  createEffect(() => {
    const initial = props.initial;
    if (props.open && initial) {
      setName(initial.name ?? '');
      setType(initial.type ?? 'click');
      setKey(initial.key ?? '');
      setUrl(initial.url ?? '');
      setMediaId(initial.media_id ?? '');
      setAppid(initial.appid ?? '');
      setPagepath(initial.pagepath ?? '');
    } else if (props.open) {
      setName('');
      setType('click');
      setKey('');
      setUrl('');
      setMediaId('');
      setAppid('');
      setPagepath('');
    }
    setError(null);
    setSubmitting(false);
  });

  const handleSubmit = (e: SubmitEvent) => {
    e.preventDefault();
    setError(null);

    const n = name().trim();
    if (!n) {
      setError('菜单名称不能为空');
      return;
    }

    const t = type();
    const button: WechatMenuButton = { name: n, type: t };

    if (t === 'click') {
      const k = key().trim();
      if (!k) {
        setError('key 不能为空');
        return;
      }
      button.key = k;
    } else if (t === 'view') {
      const u = url().trim();
      if (!u) {
        setError('url 不能为空');
        return;
      }
      button.url = u;
    } else if (t === 'miniprogram') {
      const u = url().trim();
      const a = appid().trim();
      const p = pagepath().trim();
      if (!u || !a || !p) {
        setError('url、appid、pagepath 均不能为空');
        return;
      }
      button.url = u;
      button.appid = a;
      button.pagepath = p;
    } else if (t === 'media_id') {
      const m = mediaId().trim();
      if (!m) {
        setError('media_id 不能为空');
        return;
      }
      button.media_id = m;
    }

    setSubmitting(true);
    props.onSave(button);
  };

  const title = () => {
    const base = props.mode === 'create' ? '新增' : '编辑';
    const scope = props.parentName ? `「${props.parentName}」子按钮` : '一级按钮';
    return `${base}${scope}`;
  };

  return (
    <FormModal
      open={props.open}
      title={title()}
      onSubmit={handleSubmit}
      onClose={props.onClose}
      submitting={submitting()}
      error={error()}
    >
      <FormField label="菜单名称" required>
        <input
          type="text"
          class="input input-bordered input-sm w-full"
          placeholder="例如：关于我们"
          value={name()}
          onInput={(e) => setName(e.currentTarget.value)}
          required
        />
      </FormField>

      <FormField label="类型" required>
        <select
          class="select select-bordered select-sm w-full"
          value={type()}
          onChange={(e) => setType(e.currentTarget.value as WechatMenuButton['type'])}
        >
          {TYPE_OPTIONS.map((opt) => (
            <option value={opt.value}>{opt.label}</option>
          ))}
        </select>
      </FormField>

      <Show when={type() === 'click'}>
        <FormField label="key" required hint="点击后推送的事件 key">
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="例如：ABOUT_US"
            value={key()}
            onInput={(e) => setKey(e.currentTarget.value)}
          />
        </FormField>
      </Show>

      <Show when={type() === 'view'}>
        <FormField label="url" required hint="点击后跳转的链接">
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="https://..."
            value={url()}
            onInput={(e) => setUrl(e.currentTarget.value)}
          />
        </FormField>
      </Show>

      <Show when={type() === 'miniprogram'}>
        <FormField label="url" required hint="不支持小程序时替代的跳转链接">
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="https://..."
            value={url()}
            onInput={(e) => setUrl(e.currentTarget.value)}
          />
        </FormField>
        <FormField label="appid" required hint="小程序 appid">
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="wx..."
            value={appid()}
            onInput={(e) => setAppid(e.currentTarget.value)}
          />
        </FormField>
        <FormField label="pagepath" required hint="小程序页面路径">
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="pages/index/index"
            value={pagepath()}
            onInput={(e) => setPagepath(e.currentTarget.value)}
          />
        </FormField>
      </Show>

      <Show when={type() === 'media_id'}>
        <FormField label="media_id" required hint="要下发的素材 media_id">
          <input
            type="text"
            class="input input-bordered input-sm w-full"
            placeholder="media_id"
            value={mediaId()}
            onInput={(e) => setMediaId(e.currentTarget.value)}
          />
        </FormField>
      </Show>
    </FormModal>
  );
}
