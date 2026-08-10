import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

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

async function getEnvelope<T>(path: string): Promise<T> {
  const { data } = await http.get<{ code: number; msg: string; data: T }>(path);
  return unwrapEnvelope(data);
}

export async function listRules(page: number, pageSize: number, accountId: number): Promise<RuleListResult> {
  return getEnvelope<RuleListResult>(ruleListQuery(page, pageSize, accountId));
}

export async function createRule(body: CreateRuleRequest): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(RULE_PATH.create, body);
  return unwrapEnvelope(data);
}

export async function updateRule(id: number, body: UpdateRuleRequest): Promise<void> {
  const { data } = await http.put<{ code: number; msg: string; data: null }>(ruleDetail(id), body);
  unwrapEnvelope(data);
}

export async function deleteRule(id: number): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(ruleDetail(id));
  unwrapEnvelope(data);
}

export async function listKeywords(id: number): Promise<KeywordItem[]> {
  const res = await getEnvelope<{ items: KeywordItem[] }>(ruleKeywords(id));
  return res.items;
}

export async function addKeyword(id: number, body: AddKeywordRequest): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(ruleKeywords(id), body);
  return unwrapEnvelope(data);
}

export async function removeKeyword(id: number, kid: number): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(ruleKeyword(id, kid));
  unwrapEnvelope(data);
}

export async function listReplies(id: number): Promise<ReplyItem[]> {
  const res = await getEnvelope<{ items: ReplyItem[] }>(ruleReplies(id));
  return res.items;
}

export async function addReply(id: number, body: AddReplyRequest): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(ruleReplies(id), body);
  return unwrapEnvelope(data);
}

export async function removeReply(id: number, rid: number): Promise<void> {
  const { data } = await http.delete<{ code: number; msg: string; data: null }>(ruleReply(id, rid));
  unwrapEnvelope(data);
}

export type { KeywordItem, ReplyItem, RuleItem, RuleListResult };
