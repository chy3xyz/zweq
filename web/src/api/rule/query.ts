import { deleteEnvelope, getEnvelope, postEnvelope, putEnvelope } from '#ui/api/client';

import { RULE_PATH, ruleDetail, ruleKeyword, ruleKeywords, ruleListQuery, ruleReply, ruleReplies } from './path';
import type {
  AddKeywordRequest,
  AddReplyRequest,
  CreateRuleRequest,
  KeywordItem,
  ReplyItem,
  RuleItem,
  RuleListResult,
  UpdateRuleRequest,
} from './types';

export async function listRules(page: number, pageSize: number, accountId: number): Promise<RuleListResult> {
  return getEnvelope<RuleListResult>(ruleListQuery(page, pageSize, accountId));
}

export async function createRule(body: CreateRuleRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(RULE_PATH.create, body);
}

export async function updateRule(id: number, body: UpdateRuleRequest): Promise<void> {
  await putEnvelope<null>(ruleDetail(id), body);
}

export async function deleteRule(id: number): Promise<void> {
  await deleteEnvelope<null>(ruleDetail(id));
}

export async function listKeywords(id: number): Promise<KeywordItem[]> {
  const res = await getEnvelope<{ items: KeywordItem[] }>(ruleKeywords(id));
  return res.items;
}

export async function addKeyword(id: number, body: AddKeywordRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(ruleKeywords(id), body);
}

export async function removeKeyword(id: number, kid: number): Promise<void> {
  await deleteEnvelope<null>(ruleKeyword(id, kid));
}

export async function listReplies(id: number): Promise<ReplyItem[]> {
  const res = await getEnvelope<{ items: ReplyItem[] }>(ruleReplies(id));
  return res.items;
}

export async function addReply(id: number, body: AddReplyRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(ruleReplies(id), body);
}

export async function removeReply(id: number, rid: number): Promise<void> {
  await deleteEnvelope<null>(ruleReply(id, rid));
}

export type { KeywordItem, ReplyItem, RuleItem, RuleListResult };
