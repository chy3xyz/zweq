import { getEnvelope, http, postEnvelope } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { FILE_PATH, fileDetail, fileListQuery, groupDetail, type FileListParams } from './path';
import type { FileItem, FileListResult, UploadGroup, UploadGroupListResult } from './types';

export async function listFiles(params: FileListParams = {}): Promise<FileListResult> {
  return getEnvelope<FileListResult>(fileListQuery(params));
}

/** Raw-body upload: bytes + X-File-Name + Content-Type (+ optional X-Group-Id). */
export async function uploadFile(file: File, groupId = 0): Promise<FileItem> {
  const { data } = await http.post<{ code: number; msg: string; data: FileItem }>(FILE_PATH.list, file, {
    headers: {
      'Content-Type': file.type || 'application/octet-stream',
      'X-File-Name': file.name,
      'X-Group-Id': String(groupId),
    },
  });
  return unwrapEnvelope(data);
}

export async function deleteFile(id: number): Promise<void> {
  await http.delete(fileDetail(id));
}

// ── Upload groups (image-manager categories) ──

export async function listGroups(): Promise<UploadGroup[]> {
  const res = await getEnvelope<UploadGroupListResult>(FILE_PATH.groups);
  return res.items;
}

export async function createGroup(group_name: string, sort = 0): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(FILE_PATH.groups, {
    group_name,
    sort,
  });
}

export async function updateGroup(id: number, group_name: string, sort = 0): Promise<void> {
  await http.put(groupDetail(id), { group_name, sort });
}

export async function deleteGroup(id: number): Promise<void> {
  await http.delete(groupDetail(id));
}

/**
 * Authenticated download via fetch (Authorization header + blob).
 * Exempt from the shared axios client on purpose: the axios instance carries a
 * 30s timeout and its 401 interceptor (global logout + redirect), and its
 * error messages would replace the page-visible `下载失败 (status)` text — a
 * plain fetch keeps download semantics (no timeout, no side effects) unchanged.
 */
export async function downloadFile(id: number, name: string): Promise<void> {
  const { getAuthToken } = await import('#ui/api/client');
  const token = getAuthToken();
  const resp = await fetch(fileDetail(id), {
    headers: token ? { Authorization: `Bearer ${token}` } : undefined,
  });
  if (!resp.ok) throw new Error(`下载失败 (${resp.status})`);
  const blob = await resp.blob();
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  URL.revokeObjectURL(url);
}
