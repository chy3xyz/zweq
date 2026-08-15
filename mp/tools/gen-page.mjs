#!/usr/bin/env node
// ==========================================
// unix / unibestX 页面脚手架
// 用法：node tools/gen-page.mjs <name> --title "标题" [--sub]
//   <name>  页面目录名（小写连字符，如 lucky-draw）
//   --title 页面标题（可选，默认用 name）
//   --sub   生成到 src/sub/<name>/（子包页，非 tabbar）
// 幂等：已存在的页面不会重复生成，仅提示。
// 示例：node tools/gen-page.mjs lucky-draw --title "大转盘"
// ==========================================

import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const ROOT = path.resolve(__dirname, '..')
const PAGES_JSON = path.join(ROOT, 'pages.json')

// ---- 参数解析 ----
const args = process.argv.slice(2)
const nameArg = args.find((a) => !a.startsWith('--'))
if (!nameArg) {
  console.error('用法：node tools/gen-page.mjs <name> [--title "标题"] [--sub]')
  process.exit(1)
}
const name = nameArg.toLowerCase()
const titleIdx = args.indexOf('--title')
const title = titleIdx >= 0 ? args[titleIdx + 1] : name
const isSub = args.includes('--sub')

// ---- 目录 ----
const pagesDir = isSub ? 'src/sub' : 'src/pages'
const pageDir = path.join(ROOT, pagesDir, name)
const pageFile = path.join(pageDir, `${name}.uvue`)
const relPagePath = `${pagesDir}/${name}/${name}`

if (fs.existsSync(pageFile)) {
  console.log(`⚠️  页面已存在：${relPagePath}，跳过`)
  process.exit(0)
}

// ---- 生成 uvue ----
const pageTemplate = `<template>
  <view>
    <NavBar title="${title}" :show-back="${isSub ? 'true' : 'false'}" />
    <view class="content-container pb-20px">
      <view class="mt-30px mx-30px">
        <text class="text-16px font-bold text-[#1e293b]">${title}</text>
      </view>
      <view class="mt-20rpx mx-30rpx">
        <text class="text-14px text-[#64748b]">在此编写业务内容</text>
      </view>
    </view>
  </view>
</template>

<script setup lang="uts">
// ==========================================
// ${name} 页面 — ${title}
// 二次开发指引：
// 1. 数据请求：import { http } from '@/src/http/request'
// 2. 格式化：  import { formatTime, fenToYuan } from '@/src/utils/format'
// 3. 登录态：  import { useTokenStore } from '@/src/store/token'
// ==========================================

onLoad((options: UTSJSONObject | null) => {
  if (options != null) {
    // 页面参数：options['id']
  }
})
</script>
`

fs.mkdirSync(pageDir, { recursive: true })
fs.writeFileSync(pageFile, pageTemplate, 'utf8')
console.log(`✅ 已生成页面：${relPagePath}`)

// ---- 注册 pages.json ----
const pagesJson = JSON.parse(fs.readFileSync(PAGES_JSON, 'utf8'))
const exists = pagesJson.pages.some((p) => p.path === relPagePath)
if (!exists) {
  pagesJson.pages.push({
    path: relPagePath,
    style: { navigationStyle: 'custom' },
  })
  fs.writeFileSync(PAGES_JSON, JSON.stringify(pagesJson, null, 2) + '\n', 'utf8')
  console.log(`✅ 已注册路由：pages.json → ${relPagePath}`)
} else {
  console.log(`ℹ️  路由已存在：${relPagePath}`)
}

// ---- 收尾提示 ----
console.log('')
console.log('下一步：')
console.log(`  1. 编辑 ${pageFile} 编写页面`)
console.log(`  2. 如需 tabbar 页面，在 pages.json 的 tabBar.list 中补充`)
console.log('  3. 编码前先阅读 docs/guide/dev-guide.md（二次开发指南）')
