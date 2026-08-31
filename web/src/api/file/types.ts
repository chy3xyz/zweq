export interface FileItem {
  id: number;
  name: string;
  mime: string;
  size_bytes: number;
  uploader_id: number;
  tenant_id: number;
  group_id: number;
  /** On-disk storage key; build the public URL as `/uploads/${storage_key}`. */
  storage_key: string;
  created_at: number;
}

export interface FileListResult {
  list: FileItem[];
  total: number;
  page: number;
  pageSize: number;
}

export interface UploadGroup {
  id: number;
  group_name: string;
  group_type: string;
  sort: number;
}

export interface UploadGroupListResult {
  items: UploadGroup[];
}

/** Public, same-origin URL for an uploaded file. */
export function fileUrl(item: Pick<FileItem, 'storage_key'>): string {
  return `/uploads/${item.storage_key}`;
}
