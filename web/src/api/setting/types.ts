export interface SettingItem {
  key: string;
  value: string;
  updated_at: number;
}

export interface SettingListResult {
  list: SettingItem[];
  total: number;
  page: number;
  pageSize: number;
}

/** PUT /settings/{key} — upsert body. Same shape for create & edit. */
export interface UpdateSettingRequest {
  value: string;
}
