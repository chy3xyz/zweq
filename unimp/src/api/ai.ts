import { httpPost } from '@/http/http'

export interface IAiChatRes {
  answer: string
  reasoning_content?: string
  budget_exhausted?: boolean
}

/**
 * C 端 AI 助手：走后端 zigmodu AI 引擎（与后台 Chat / 微信自动回复同一服务）。
 * 不建 session、不落库；配额/熔断/并发舱壁由后端 AiService 控制。
 */
export function chatWithAi(content: string) {
  // 错误由 AI 页面渲染成气泡，避免再弹一层 toast
  return httpPost<IAiChatRes>('/api/v1/app/ai/chat', { content }, undefined, undefined, { hideErrorToast: true })
}
