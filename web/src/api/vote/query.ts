import { http } from '#ui/api/client';
import { unwrapEnvelope } from '#ui/api/envelope';

import { voteListQuery, VOTE_PATH } from './path';
import type { CreateVoteRequest, VoteItem, VoteListResult } from './types';

export async function listVotes(
  accountId: number,
  page: number,
  pageSize: number,
): Promise<VoteListResult> {
  const { data } = await http.get<{ code: number; msg: string; data: VoteListResult }>(
    voteListQuery(accountId, page, pageSize),
  );
  return unwrapEnvelope(data);
}

export async function createVote(body: CreateVoteRequest): Promise<{ id: number }> {
  const { data } = await http.post<{ code: number; msg: string; data: { id: number } }>(
    VOTE_PATH.create,
    body,
  );
  return unwrapEnvelope(data);
}

export async function getVoteResults(id: number): Promise<number[]> {
  const { data } = await http.get<{ code: number; msg: string; data: { tally: number[] } }>(
    VOTE_PATH.results(id),
  );
  return unwrapEnvelope(data).tally;
}

export async function castVote(id: number, openid: string, option_index: number): Promise<void> {
  const { data } = await http.post<{ code: number; msg: string; data: null }>(VOTE_PATH.cast(id), {
    openid,
    option_index,
  });
  unwrapEnvelope(data);
}

export type { CreateVoteRequest, VoteItem, VoteListResult };
