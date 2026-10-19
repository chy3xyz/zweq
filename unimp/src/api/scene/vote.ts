import { httpGet, httpPost } from '@/http/http'
import { DEFAULT_ACCOUNT_ID } from '@/utils/env'
import type { IPaged } from '../shop-product'

export interface IVote {
  id: number
  account_id: number
  title: string
  options_json: string
  end_at: number
  created_at: number
}

export interface IVoteDetail {
  id: number
  title: string
  options_json: string
  end_at: number
  tally: number[]
}

export function listVotes(page: number, pageSize: number, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpGet<IPaged<IVote>>('/api/v1/app/votes', {
    account_id: accountId,
    page,
    page_size: pageSize,
  })
}

export function getVoteDetail(id: number) {
  return httpGet<IVoteDetail>(`/api/v1/app/votes/${id}`)
}

export function voteBallot(id: number, optionIndex: number, accountId: number = DEFAULT_ACCOUNT_ID) {
  return httpPost<Record<string, never>>(`/api/v1/app/votes/${id}/ballot`, {
    account_id: accountId,
    option_index: optionIndex,
  })
}
