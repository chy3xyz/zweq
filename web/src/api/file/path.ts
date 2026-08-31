import { APP_CONFIG } from '#ui/config';

export const FILE_PATH = {
  list: `${APP_CONFIG.apiPrefix}/files`,
  groups: `${APP_CONFIG.apiPrefix}/files/groups`,
} as const;

export const fileDetail = (id: number) => `${APP_CONFIG.apiPrefix}/files/${id}`;

export interface FileListParams {
  page?: number;
  pageSize?: number;
  groupId?: number;
  /** Mime prefix filter, e.g. "image/" to list only images. */
  type?: string;
}

export const fileListQuery = (params: FileListParams = {}) => {
  const sp = new URLSearchParams();
  sp.set('page', String(params.page ?? 1));
  sp.set('page_size', String(params.pageSize ?? 20));
  if (params.groupId && params.groupId > 0) sp.set('group_id', String(params.groupId));
  if (params.type) sp.set('type', params.type);
  return `${FILE_PATH.list}?${sp.toString()}`;
};

export const groupDetail = (id: number) => `${FILE_PATH.groups}/${id}`;
