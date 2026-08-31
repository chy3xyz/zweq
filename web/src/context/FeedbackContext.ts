import { createContext } from 'solid-js';

export type ToastKind = 'success' | 'error' | 'info';

export type ConfirmOptions = {
  title?: string;
  message: string;
  confirmText?: string;
  cancelText?: string;
  danger?: boolean;
};

export type FeedbackActions = {
  /** Transient top-center notification (`el-message` equivalent). */
  toast: (message: string, kind?: ToastKind) => void;
  /** Promise-based confirm box (`ElMessageBox.confirm` equivalent). */
  confirm: (options: ConfirmOptions | string) => Promise<boolean>;
  /** Run an action with a confirm gate + success/error toast + reload. */
  runAction: (options: {
    confirm?: ConfirmOptions | string;
    action: () => Promise<unknown>;
    success?: string;
    onDone?: () => void;
  }) => Promise<void>;
};

export const FeedbackContext = createContext<FeedbackActions>({
  toast: () => {},
  confirm: async () => false,
  runAction: async () => {},
});
