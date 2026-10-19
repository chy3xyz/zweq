/**
 * 通用格式化工具 — 金额 / 时间 / 相对时间
 * 服务端金额单位统一为「分」，时间统一为「秒级时间戳」。
 */

/** 金额分 → 元字符串（1250 → "12.50"） */
export function fenToYuan(fen: number): string {
  const abs = fen < 0 ? -fen : fen
  const yuan = Math.floor(abs / 100)
  const rest = abs % 100
  const restStr = rest < 10 ? `0${rest}` : `${rest}`
  return fen < 0 ? `-${yuan}.${restStr}` : `${yuan}.${restStr}`
}

/** 金额分 → 带 ¥ 符号字符串 */
export function formatMoney(fen: number): string {
  return `¥${fenToYuan(fen)}`
}

function pad2(n: number): string {
  return n < 10 ? `0${n}` : `${n}`
}

/** 秒级时间戳 → "YYYY-MM-DD HH:mm" */
export function formatTime(ts: number): string {
  if (ts <= 0)
    return '-'
  const d = new Date(ts * 1000)
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`
}

/** 秒级时间戳 → "YYYY-MM-DD" */
export function formatDate(ts: number): string {
  if (ts <= 0)
    return '-'
  const d = new Date(ts * 1000)
  return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())}`
}

/** 相对时间：刚刚 / N 分钟前 / N 小时前 / 昨天 / N 天前 */
export function relativeTime(ts: number): string {
  if (ts <= 0)
    return '-'
  const diff = Math.floor(Date.now() / 1000) - ts
  if (diff < 60)
    return '刚刚'
  if (diff < 3600)
    return `${Math.floor(diff / 60)} 分钟前`
  if (diff < 86400)
    return `${Math.floor(diff / 3600)} 小时前`
  if (diff < 172800)
    return '昨天'
  return `${Math.floor(diff / 86400)} 天前`
}
