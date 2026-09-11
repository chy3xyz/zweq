import { deleteEnvelope, getEnvelope, postEnvelope, putEnvelope } from '#ui/api/client';

import { voteListQuery, VOTE_PATH } from './path';
import type {
  CreateVoteRequest,
  UpdateVoteRequest,
  VoteItem,
  VoteListResult,
} from './types';

export async function listVotes(
  accountId: number,
  page: number,
  pageSize: number,
): Promise<VoteListResult> {
  return getEnvelope<VoteListResult>(
    voteListQuery(accountId, page, pageSize),
  );
}

export async function createVote(body: CreateVoteRequest): Promise<{ id: number }> {
  return postEnvelope<{ id: number }>(
    VOTE_PATH.create,
    body,
  );
}

export async function getVoteResults(id: number): Promise<number[]> {
  const res = await getEnvelope<{ tally: number[] }>(VOTE_PATH.results(id));
  return res.tally;
}

export async function updateVote(id: number, body: UpdateVoteRequest): Promise<{ id: number }> {
  return putEnvelope<{ id: number }>(
    VOTE_PATH.vote(id),
    body,
  );
}

export async function deleteVote(id: number): Promise<void> {
  await deleteEnvelope<null>(VOTE_PATH.vote(id));
}

export async function castVote(id: number, openid: string, option_index: number): Promise<void> {
  await postEnvelope<null>(VOTE_PATH.cast(id), {
    openid,
    option_index,
  });
}

export type { CreateVoteRequest, UpdateVoteRequest, VoteItem, VoteListResult };
