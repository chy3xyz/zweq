import { deleteEnvelope, getEnvelope, postEnvelope, putEnvelope } from '#ui/api/client';

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
  return getEnvelope<MemberLevelListResult>(
    memberLevelsQuery(accountId, page, pageSize, keyword, status),
  );
}

export async function createMemberLevel(body: CreateLevelRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(
    MEMBER_CARD_PATH.create,
    body,
  );
}

/** 启用 / 停用会员等级：停用的等级不再自动分配给新开的会员卡。 */
export async function setMemberLevelStatus(id: number, status: number): Promise<void> {
  await putEnvelope<null>(
    MEMBER_CARD_PATH.levelStatus(id),
    { status },
  );
}

/** 整体更新等级（account 作用域不变，请求体不含 account_id）。 */
export async function updateMemberLevel(id: number, body: UpdateLevelRequest): Promise<{ id: number }> {
  return putEnvelope<{ id: number }>(
    MEMBER_CARD_PATH.memberLevel(id),
    body,
  );
}

/** 删除等级（不级联）：等级下仍有会员时后端返回 400「该等级下存在会员，无法删除」。 */
export async function deleteMemberLevel(id: number): Promise<void> {
  await deleteEnvelope<null>(
    MEMBER_CARD_PATH.memberLevel(id),
  );
}

export async function listMembers(
  accountId: number,
  page: number,
  pageSize: number,
  keyword = '',
): Promise<MemberAccountListResult> {
  return getEnvelope<MemberAccountListResult>(
    membersQuery(accountId, page, pageSize, keyword),
  );
}

export async function getMemberView(accountId: number, openid: string): Promise<MemberView | null> {
  return getEnvelope<MemberView | null>(
    memberViewQuery(accountId, openid),
  );
}

export async function openMemberCard(accountId: number, openid: string): Promise<void> {
  await postEnvelope<null>(
    `${MEMBER_CARD_PATH.open}?account_id=${accountId}`,
    { openid },
  );
}

export async function adjustMemberPoints(accountId: number, openid: string, delta: number): Promise<void> {
  await postEnvelope<null>(
    `${MEMBER_CARD_PATH.adjust}?account_id=${accountId}`,
    { openid, delta },
  );
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
