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
  UpdateLevelRequest,
} from './types';

export async function listMemberLevels(
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
  status = -1,
): Promise<MemberLevelListResult> {
  const { data } = await http.get<{ code: number; msg: string; data: MemberLevelListResult }>(
    memberLevelsQuery(accountId, page, pageSize, keyword, status),
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

/** 启用 / 停用会员等级：停用的等级不再自动分配给新开的会员卡。 */
export async function setMemberLevelStatus(id: number, status: number): Promise<void> {
  const { data } = await http.put<{ code: number; msg: string; data: null }>(
    MEMBER_CARD_PATH.levelStatus(id),
    { status },
  );
  unwrapEnvelope(data);
}

/** 整体更新等级（account 作用域不变，请求体不含 account_id）。 */
export async function updateMemberLevel(id: number, body: UpdateLevelRequest): Promise<{ id: number }> {
  const { data } = await http.put<{ code: number; msg: string; data: { id: number } }>(
    MEMBER_CARD_PATH.memberLevel(id),
    body,
  );
  return unwrapEnvelope(data);
}

/** 删除等级（不级联）：等级下仍有会员时后端返回 400「该等级下存在会员，无法删除」。 */
export async function deleteMemberLevel(id: number): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(
    MEMBER_CARD_PATH.memberLevel(id),
  );
  unwrapEnvelope(data);
}

export async function listMembers(
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
): Promise<MemberAccountListResult> {
  const { data } = await http.get<{ code: number; msg: string; data: MemberAccountListResult }>(
    membersQuery(accountId, page, pageSize, keyword),
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
  UpdateLevelRequest,
};
