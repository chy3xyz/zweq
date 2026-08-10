export type AccountKind = 'wechat' | 'wxapp' | 'app';
export type AccountStatus = 'active' | 'disabled';

export interface AccountItem {
  id: number;
  tenant_id: number;
  name: string;
  kind: AccountKind;
  status: AccountStatus;
  created_at: number;
  updated_at: number;
}

export interface AccountListResult {
  list: AccountItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface CreateAccountRequest {
  name: string;
  kind: AccountKind;
}

export interface UpdateAccountRequest {
  name?: string;
  kind?: AccountKind;
  status?: AccountStatus;
}

/** WeChat config — secrets are never returned by the backend. */
export interface WechatConfigItem {
  account_id: number;
  appid: string;
  token: string;
  verified: boolean;
}

export interface SetWechatConfigRequest {
  appid: string;
  token: string;
  secret?: string;
  encoding_aes_key?: string;
  verified?: boolean;
}
