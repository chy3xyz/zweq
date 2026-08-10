import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { fileDetail, MATERIAL_PATH, newsDetail, pagedQuery } from './path';
import type {
  CreateFileRequest,
  CreateNewsRequest,
  MaterialFileItem,
  MaterialFileListResult,
  NewsItem,
  NewsListResult,
  UpdateNewsRequest,
} from './types';

async function getEnvelope<T>(path: string): Promise<T> {
  const { data } = await http.get<{ code: number; msg: string; data: T }>(path);
  return unwrapEnvelope(data);
}

export async function listNews(page: number, pageSize: number, accountId: number): Promise<NewsListResult> {
  return getEnvelope<NewsListResult>(pagedQuery(MATERIAL_PATH.news, page, pageSize, accountId));
}

export async function createNews(body: CreateNewsRequest): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(MATERIAL_PATH.news, body);
  return unwrapEnvelope(data);
}

export async function updateNews(id: number, body: UpdateNewsRequest): Promise<void> {
  const { data } = await http.put<{ code: number; msg: string; data: null }>(newsDetail(id), body);
  unwrapEnvelope(data);
}

export async function deleteNews(id: number): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(newsDetail(id));
  unwrapEnvelope(data);
}

export async function listMaterialFiles(page: number, pageSize: number, accountId: number, kind?: string): Promise<MaterialFileListResult> {
  return getEnvelope<MaterialFileListResult>(pagedQuery(MATERIAL_PATH.files, page, pageSize, accountId, kind));
}

export async function createMaterialFile(body: CreateFileRequest): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(MATERIAL_PATH.files, body);
  return unwrapEnvelope(data);
}

export async function deleteMaterialFile(id: number): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(fileDetail(id));
  unwrapEnvelope(data);
}

export type { MaterialFileItem, NewsItem };
