export interface ModuleItem {
  id: number;
  name: string;
  title: string;
  version: string;
  status: 'active' | 'disabled';
  created_at: number;
  updated_at: number;
}

export interface ModuleListResult {
  list: ModuleItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface BindingItem {
  id: number;
  account_id: number;
  module: string;
  status: 'active' | 'disabled';
}

export interface RegisterModuleRequest {
  name: string;
  title: string;
  version: string;
}

export interface BindModuleRequest {
  module: string;
  status?: 'active' | 'disabled';
}
