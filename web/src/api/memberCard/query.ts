import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { memberLevelsQuery, membersQuery, memberViewQuery, MEMBER_CARD_PATH } from './path';
import type {
  CreateLevelRequest,
  MemberAccountItem,
  MemberAccountListResult,
  MemberCardLevelItem,
  MemberLevelListResult,
  MemberView,
} from './types';

export async function listMemberLevels(
  accountId: number,
  page: number,
  pageSize: number,
): Promise<MemberLevelListResult> {
  const { data } = await http.get<{ code: number; msg: string; data: MemberLevelListResult }>(
    memberLevelsQuery(accountId, page, pageSize),
  );
  return unwrapEnvelope(data);
}

export async function createMemberLevel(body: CreateLevelRequest): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(
    MEMBER_CARD_PATH.create,
    body,
  );
  return unwrapEnvelope(data);
}

export async function listMembers(
  accountId: number,
  page: number,
  pageSize: number,
): Promise<MemberAccountListResult> {
  const { data } = await http.get<{ code: number; msg: string; data: MemberAccountListResult }>(
    membersQuery(accountId, page, pageSize),
  );
  return unwrapEnvelope(data);
}

export async function getMemberView(accountId: number, openid: string): Promise<MemberView | null> {
  const { data } = await http.get<{ code: number; msg: string; data: MemberView | null }>(
    memberViewQuery(accountId, openid),
  );
  return unwrapEnvelope(data);
}

export async function openMemberCard(accountId: number, openid: string): Promise<void> {
  const { data } = await http.post<{ code: number; msg: string; data: null }>(MEMBER_CARD_PATH.open, {
    openid,
  });
  unwrapEnvelope(data);
}

export async function adjustMemberPoints(accountId: number, openid: string, delta: number): Promise<void> {
  const { data } = await http.post<{ code: number; msg: string; data: null }>(MEMBER_CARD_PATH.adjust, {
    openid,
    delta,
  });
  unwrapEnvelope(data);
}

export type {
  CreateLevelRequest,
  MemberAccountItem,
  MemberAccountListResult,
  MemberCardLevelItem,
  MemberLevelListResult,
  MemberView,
};
