import { createEffect, createSignal, For, onMount, Show, type JSX } from 'solid-js';

import ImageManager from '#ui/components/ImageManager';
import { fileUrl } from '#ui/api/file/types';
import type { FileItem } from '#ui/api/file/types';

interface Props {
  value: string;
  onInput: (html: string) => void;
  placeholder?: string;
  class?: string;
}

interface ToolButton {
  cmd?: string;
  arg?: string;
  label: string;
  title: string;
  isBlock?: boolean;
}

const TOOLS: ToolButton[] = [
  { cmd: 'bold', label: 'B', title: '加粗' },
  { cmd: 'italic', label: 'I', title: '斜体' },
  { cmd: 'underline', label: 'U', title: '下划线' },
  { cmd: 'formatBlock', arg: 'H2', label: 'H2', title: '标题' },
  { cmd: 'formatBlock', arg: 'BLOCKQUOTE', label: '❝', title: '引用' },
  { cmd: 'insertUnorderedList', label: '• 列表', title: '无序列表' },
  { cmd: 'insertOrderedList', label: '1. 列表', title: '有序列表' },
  { cmd: 'createLink', label: '🔗', title: '插入链接' },
];

/**
 * Zero-dependency rich text editor over a `contentEditable` surface. Emits raw
 * HTML via `onInput`. The image button opens the shared `ImageManager` and
 * inserts the chosen image at the caret. The editable surface is only synced
 * from `value` when it diverges from the DOM, so typing never loses the caret.
 */
export default function RichEditor(props: Props) {
  let ref: HTMLDivElement | undefined;
  const [pickerOpen, setPickerOpen] = createSignal(false);
  const [lastHtml, setLastHtml] = createSignal(props.value);

  onMount(() => {
    if (ref) ref.innerHTML = props.value ?? '';
  });

  // External resets (e.g. form clear) flow in through `value`.
  createEffect(() => {
    const v = props.value ?? '';
    if (ref && v !== lastHtml() && v !== ref.innerHTML) {
      ref.innerHTML = v;
      setLastHtml(v);
    }
  });

  const emit = () => {
    if (!ref) return;
    setLastHtml(ref.innerHTML);
    props.onInput(ref.innerHTML);
  };

  const exec = (t: ToolButton) => {
    ref?.focus();
    if (t.cmd === 'createLink') {
      const url = window.prompt('链接地址：', 'https://');
      if (!url) return;
      document.execCommand('createLink', false, url);
    } else if (t.cmd === 'formatBlock') {
      document.execCommand('formatBlock', false, t.arg ?? 'DIV');
    } else if (t.cmd) {
      document.execCommand(t.cmd, false, t.arg ?? '');
    }
    emit();
  };

  let savedRange: Range | null = null;
  const saveSelection = () => {
    const sel = window.getSelection();
    if (sel && sel.rangeCount > 0 && ref?.contains(sel.anchorNode)) {
      savedRange = sel.getRangeAt(0).cloneRange();
    }
  };
  const restoreSelection = () => {
    ref?.focus();
    const sel = window.getSelection();
    if (!sel) return;
    sel.removeAllRanges();
    if (savedRange) sel.addRange(savedRange);
  };

  const insertImage = (items: FileItem[]) => {
    restoreSelection();
    for (const item of items) {
      const img = document.createElement('img');
      img.src = fileUrl(item);
      img.alt = item.name;
      img.style.maxWidth = '100%';
      img.className = 'rounded my-2';
      const sel = window.getSelection();
      if (sel && savedRange) {
        savedRange.insertNode(img);
        savedRange.setStartAfter(img);
        savedRange.collapse(true);
      } else if (ref) {
        ref.appendChild(img);
      }
    }
    setPickerOpen(false);
    emit();
  };

  return (
    <div class={`flex flex-col rounded border border-base-300 bg-base-100 ${props.class ?? ''}`}>
      <div class="flex flex-wrap items-center gap-1 border-b border-base-200 bg-base-200/50 p-1.5">
        <For each={TOOLS}>
          {(t) => (
            <button
              type="button"
              class="btn btn-ghost btn-xs px-2 font-semibold"
              title={t.title}
              onClick={() => exec(t)}
            >
              <span class="text-sm">{t.label}</span>
            </button>
          )}
        </For>
        <button type="button" class="btn btn-ghost btn-xs px-2" title="插入图片" onClick={() => {
          saveSelection();
          setPickerOpen(true);
        }}>
          🖼 图片
        </button>
        <button type="button" class="btn btn-ghost btn-xs px-2" title="清除格式" onClick={() => {
          document.execCommand('removeFormat');
          emit();
        }}>
          清除
        </button>
      </div>
      <div
        ref={ref}
        contentEditable
        class="prose max-w-none min-h-[200px] flex-1 overflow-y-auto px-3 py-2 text-sm leading-6 outline-none focus:ring-1 focus:ring-primary/40"
        data-placeholder={props.placeholder ?? '请输入正文…'}
        onInput={emit}
        onBlur={emit}
        style={{ 'white-space': 'pre-wrap' } as JSX.CSSProperties}
      />
      <Show when={pickerOpen()}>
        <ImageManager
          open={pickerOpen()}
          multiple
          max={9}
          onSelect={insertImage}
          onClose={() => setPickerOpen(false)}
        />
      </Show>
    </div>
  );
}
