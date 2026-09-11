import { deleteEnvelope, getEnvelope, postEnvelope, putEnvelope } from '#ui/api/client';

import { USER_PATH, userDetail, userListQuery, userRevokeSessions } from './path';
import type {
  CreateUserRequest,
  UpdateUserRequest,
  UserListResult,
} from './types';

export async function listUsers(
  page: number,
  pageSize: number,
  keyword?: string,
): Promise<UserListResult> {
  return getEnvelope<UserListResult>(userListQuery(page, pageSize, keyword));
}

export async function createUser(body: CreateUserRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(USER_PATH.create, body);
}

export async function updateUser(id: number, body: UpdateUserRequest): Promise<void> {
  await putEnvelope<null>(userDetail(id), body);
}

export async function deleteUser(id: number): Promise<void> {
  await deleteEnvelope<null>(userDetail(id));
}

export async function revokeUserSessions(id: number): Promise<void> {
  await postEnvelope<null>(userRevokeSessions(id), {});
}
