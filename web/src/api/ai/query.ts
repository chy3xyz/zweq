import { getEnvelope, http, postEnvelope, putEnvelope } from '#ui/api/client';

import {
  AI_PATH,
  aiApprovalResolve,
  aiApprovalsQuery,
  aiProviderCheck,
  aiProviderDetail,
  aiProvidersQuery,
  aiRunsQuery,
  aiSessionChat,
  aiSessionDetail,
  aiSessionMessages,
  aiSessionsQuery,
} from './path';
import type {
  AiApprovalListResult,
  AiChatResult,
  AiMessageListResult,
  AiProviderListResult,
  AiRunListResult,
  AiSessionListResult,
  AiSkillsResult,
  AiWorkflowResult,
} from './types';

export async function listAiSessions(page: number, pageSize: number): Promise<AiSessionListResult> {
  return getEnvelope<AiSessionListResult>(aiSessionsQuery(page, pageSize));
}

export async function createAiSession(title: string): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(AI_PATH.sessions, { title });
}

export async function listAiMessages(sessionId: number): Promise<AiMessageListResult> {
  return getEnvelope<AiMessageListResult>(aiSessionMessages(sessionId));
}

export async function chatAi(sessionId: number, content: string): Promise<AiChatResult> {
  return postEnvelope<AiChatResult>(aiSessionChat(sessionId), { content });
}

export async function deleteAiSession(sessionId: number): Promise<void> {
  await http.delete(aiSessionDetail(sessionId));
}

export async function listAiProviders(page: number, pageSize: number): Promise<AiProviderListResult> {
  return getEnvelope<AiProviderListResult>(aiProvidersQuery(page, pageSize));
}

export async function createAiProvider(body: {
  name: string;
  endpoint: string;
  /** One or more provider keys; the backend stores them encrypted. */
  api_keys: string[];
  models: string;
  fallback_providers?: string;
  enabled?: boolean;
}): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(AI_PATH.providers, body);
}

export async function updateAiProvider(
  id: number,
  body: Partial<{
    name: string;
    endpoint: string;
    /** Omit to keep the existing keys (they are never returned by the API). */
    api_keys: string[];
    models: string;
    fallback_providers: string;
    enabled: boolean;
  }>,
): Promise<void> {
  await putEnvelope<null>(aiProviderDetail(id), body);
}

export async function deleteAiProvider(id: number): Promise<void> {
  await http.delete(aiProviderDetail(id));
}

export async function checkAiProvider(id: number): Promise<{ status: string }> {
  return postEnvelope<{ status: string }>(aiProviderCheck(id));
}

export async function listAiApprovals(page: number, pageSize: number, status?: string): Promise<AiApprovalListResult> {
  return getEnvelope<AiApprovalListResult>(aiApprovalsQuery(page, pageSize, status));
}

export async function resolveAiApproval(id: number, action: 'approve' | 'reject'): Promise<void> {
  await postEnvelope<null>(aiApprovalResolve(id, action));
}

export async function listAiRuns(page: number, pageSize: number): Promise<AiRunListResult> {
  return getEnvelope<AiRunListResult>(aiRunsQuery(page, pageSize));
}

export async function runAiWorkflow(): Promise<AiWorkflowResult> {
  return postEnvelope<AiWorkflowResult>(AI_PATH.workflowRun);
}

/** Read-only list of registered AI skills (agent capabilities). */
export async function listAiSkills(): Promise<AiSkillsResult> {
  return getEnvelope<AiSkillsResult>(AI_PATH.skills);
}

/** Prometheus-format metrics text from the AI module (raw, not an envelope). */
export async function listAiMetrics(): Promise<string> {
  const { data } = await http.get<string>(AI_PATH.metrics, { responseType: 'text' });
  return data;
}
