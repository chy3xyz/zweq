import { deleteEnvelope, getEnvelope, postEnvelope, putEnvelope } from '#ui/api/client';

import { fileDetail, MATERIAL_PATH, newsDetail, pagedQuery } from './path';
import type {
  CreateFileRequest,
  CreateNewsRequest,
  MaterialFileItem,
  MaterialFileListResult,
  MaterialKind,
  NewsItem,
  NewsListResult,
  UpdateNewsRequest,
  UploadNewsRequest,
} from './types';

export async function listNews(
  page: number,
  pageSize: number,
  accountId: number,
  keyword = '',
): Promise<NewsListResult> {
  return getEnvelope<NewsListResult>(pagedQuery(MATERIAL_PATH.news, page, pageSize, accountId, '', keyword));
}

export async function createNews(body: CreateNewsRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(MATERIAL_PATH.news, body);
}

export async function updateNews(id: number, body: UpdateNewsRequest): Promise<void> {
  await putEnvelope<null>(newsDetail(id), body);
}

export async function deleteNews(id: number): Promise<void> {
  await deleteEnvelope<null>(newsDetail(id));
}

export async function listMaterialFiles(page: number, pageSize: number, accountId: number, kind?: string): Promise<MaterialFileListResult> {
  return getEnvelope<MaterialFileListResult>(pagedQuery(MATERIAL_PATH.files, page, pageSize, accountId, kind));
}

export async function createMaterialFile(body: CreateFileRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(MATERIAL_PATH.files, body);
}

export async function deleteMaterialFile(id: number): Promise<void> {
  await deleteEnvelope<null>(fileDetail(id));
}

export async function syncNews(accountId: number): Promise<void> {
  await postEnvelope<null>(
    `${MATERIAL_PATH.syncNews}?${new URLSearchParams({ account_id: String(accountId) }).toString()}`,
  );
}

export async function syncFiles(accountId: number, kind: MaterialKind): Promise<void> {
  await postEnvelope<null>(
    `${MATERIAL_PATH.syncFiles}?${new URLSearchParams({ account_id: String(accountId), kind }).toString()}`,
  );
}

export async function uploadNews(body: UploadNewsRequest): Promise<{ media_id: string }> {
  return postEnvelope<{ media_id: string }>(
    MATERIAL_PATH.uploadNews,
    body,
  );
}

export type { MaterialFileItem, NewsItem };
