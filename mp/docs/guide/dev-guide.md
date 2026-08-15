# 二次开发指南（Dev Guide）

本指南面向在 unix/unibestX 基础上开发业务页面的开发者。编码前请先阅读
`.agents/rules/uniappx.md`（uni-app X 平台限制与规范）与 `docs/guide/uts-tips.md`（UTS 技巧）。

## 1. 目录结构速览

```
unix/
├── App.uvue            # 应用根组件（全局主题、生命周期）
├── main.uts            # 入口：pinia / i18n / uview-ultra / 路由拦截器
├── manifest.json       # 应用配置：appid、各端设置
├── pages.json          # 页面路由 + tabBar + easycom
├── src/
│   ├── pages/          # tabbar 页（index / basic / function / me）
│   ├── sub/            # 子包页（auth/login、业务页，可分包）
│   ├── components/     # 通用组件（NavBar 等）
│   ├── layouts/        # 布局
│   ├── api/            # 后端 API 客户端（auth.uts / points.uts ...）
│   ├── http/           # 请求封装（lime-request + 拦截器）
│   ├── store/          # pinia：token / user / app
│   ├── utils/          # 工具（format / env / systemInfo ...）
│   ├── router/         # 路由配置与拦截器
│   ├── tabbar/         # tabbar 状态
│   ├── i18n/           # 国际化
│   └── style/          # 全局样式
├── uni_modules/        # 三方组件（uview-ultra / lime-request ...）
└── tools/              # 脚手架脚本（gen-page.mjs）
```

## 2. 新增页面（推荐脚手架）

```bash
node tools/gen-page.mjs lucky-draw --title "大转盘"
# 生成 src/pages/lucky-draw/lucky-draw.uvue 并自动注册 pages.json
```

子包页（非 tabbar，推荐放业务页）：

```bash
node tools/gen-page.mjs checkin --title "签到" --sub
# 生成 src/sub/checkin/checkin.uvue
```

手动创建时注意 `pages.json` 需注册 `path` + `style.navigationStyle: "custom"`
（配合 NavBar 组件使用）。

## 3. 新增 API 客户端

在 `src/api/` 下按域建文件，遵循既有模式（`auth.uts` / `points.uts`）：

```ts
// src/api/luckyDraw.uts
import { http } from '../http/request'
import type { IPagedList } from './points'   // 复用分页类型

export type ILuckyDrawRecord = {
  id: number
  openid: string
  prize_name: string
  points: number
  created_at: number
}

export function listLuckyDrawRecords(
  accountId: number,
  page: number = 1,
  pageSize: number = 20,
): Promise<IPagedList<ILuckyDrawRecord>> {
  const query = `account_id=${accountId}&page=${page}&page_size=${pageSize}`
  return http.get<IPagedList<ILuckyDrawRecord>>(`/api/v1/lucky-draw/records?${query}`)
}
```

## 4. 对接后端约定

- **请求封装**：`src/http/request.uts`（已内置 envelope 解包、401 跳登录、toast）
- **鉴权头**：登录后自动携带 `Authorization: Bearer <token>`
- **响应格式**：`{ code, msg, data }`，`code === 0` 为成功；`http.get<T>` 返回的是解包后的 `data`
- **域名**：H5 走 Vite 代理 `/api → 127.0.0.1:18080`（vite.config.ts）；非 H5 硬编码于 request.uts
- **金额单位**：服务端一律「分」，展示用 `fenToYuan` / `formatMoney`
- **时间单位**：服务端一律「秒级时间戳」，展示用 `formatTime` / `relativeTime`

## 5. 通用工具（src/utils/format.uts）

| 函数 | 说明 |
|---|---|
| `fenToYuan(fen)` | 分 → 元字符串 `"12.50"` |
| `formatMoney(fen)` | `"¥12.50"` |
| `formatTime(ts)` | 秒级时间戳 → `"2026-08-14 18:30"` |
| `formatDate(ts)` | → `"2026-08-14"` |
| `relativeTime(ts)` | 刚刚 / N 分钟前 / 昨天 ... |

## 6. 开发规范速记（uni-app X）

- 禁止浏览器 API（window/document）；App 端编译为原生
- `<button>` 禁止 flex 对齐属性；`<view>` 禁止 color 属性（移到 `<text>`）
- 边框用三件套：`border-width-1px border-color-[#ccc] border-solid`
- CSS 变量换肤需在根 view 内联绑定；原生控件用行内 style
- 每次编辑 `.uts/.uvue` 前调用 `uniapp-x-skill`（项目 `.agents/skills/`），按其预防优先流程执行

## 7. 与 zweq 后端对接（小程序模板）

- 管理端登录：`POST /api/v1/auth/login`（email/password）→ 存 token store
- 微信登录（MP-WEIXIN）：`POST /api/v1/miniprogram/login`（account_id/code）
- 场景接口：积分商城 / 优惠券 / 抽奖 / 投票 / 秒杀 / 会员卡 / 分销均已有 API 客户端示例
- 粉丝在公众号的互动走消息接收器（Receiver），小程序做展示与运营管理
