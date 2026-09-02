# unix 子仓体验补全设计：me 入口 + H5 测试登录

> 目标仓库：`unix/`（uni-app X / unibestX 子仓）
> 关联后端：本地 `http://localhost:8000`（已在运行，pid 29670）

## 背景

`unix/` 是 C 端 uni-app X 应用，当前 me 页缺少与首页宫格对应的「会员卡」「分销」入口；H5 端登录页仅提示「暂不支持微信登录」，导致 H5 调试和后台功能验证受阻。

## 设计目标

1. me 页补齐两个高频入口（会员卡、分销）。
2. H5 端支持一键测试账号登录，本地联调指向 `localhost:8000`。
3. 删除无意义的 mock 示例文件。

## 后端行为确认

- `POST /api/v1/shop/auth/login` 对不存在的 `openid` 会自动创建粉丝并签发 fan token，因此 H5 测试登录可直接复用 `cLogin(openid)`，无需新增后端接口。
- 后端已在本地 8000 运行，登录后可异步拉取 `getFanProfile()`。

## 改动清单

### 1. me 页新增入口

文件：`unix/src/pages/me/me.uvue`

- 在「我的订单」「我的券」「钱包」三行下方追加：
  - 会员卡 → `/src/sub/marketing/member-card/member-card`
  - 分销 → `/src/sub/marketing/distribution/distribution`
- 视觉与现有三行保持一致：
  - 容器：`h-48px rounded-8px bg-[#f8fafc] flex items-center justify-between px-12px mb-12px`
  - 左侧：图标 + 标题
  - 右侧：箭头图标
- 新增方法：
  - `goMemberCard()`：`uni.navigateTo({ url: '/src/sub/marketing/member-card/member-card' })`
  - `goDistribution()`：`uni.navigateTo({ url: '/src/sub/marketing/distribution/distribution' })`
- 两个子包页已注册路由且内部自行处理未登录跳转，me 页无需传参或鉴权判断。

### 2. H5 测试登录

文件：`unix/src/sub/auth/login.uvue`

- 替换 `#ifndef MP-WEIXIN` 分支的「暂不支持微信登录」toast。
- 新增 UI（仅 H5/App 编译进包，小程序端不打包）：
  - openid 输入框：
    - 默认值 `dev_${Date.now()}`
    - placeholder：`请输入测试 openid`
  - 「测试账号登录」按钮
- 点击后逻辑：
  1. 校验 openid 非空，空则 toast「请输入 openid」。
  2. 调用 `cLogin(openid)`（来自 `src/api/auth.uts`）。
  3. 成功后写入 `FanStore`：`setOpenid(openid)`、`setFanToken(token)`。
  4. toast「登录成功」。
  5. 调用现有 `redirectAfterLogin()` 返回上一页。
  6. 异步调用 `getFanProfile()` 填充头像昵称。
- 错误处理沿用现有 toast + console.error。

### 3. H5 开发环境指向本地 8000

文件：`unix/.env.development`（新增）

```env
VITE_SERVER_BASEURL=http://localhost:8000
```

说明：
- `request.uts` 中 H5 优先读取 `import.meta.env.VITE_SERVER_BASEURL`。
- 当前 `unix/` 下无 `.env` 文件，H5 会回退到远程 `laf.run`。
- 新增 `.env.development` 后，`pnpm dev`（H5）会指向本地 8000。

### 4. 删除 mock 示例

文件：`unix/src/api/foo.uts`

- 该文件为早期示例，按规范删除。

## 验证计划

1. `cd unix && pnpm build:h5` 构建成功。
2. `pnpm dev` 启动 H5（端口 9001），访问登录页，使用默认 openid 登录成功。
3. 登录后进入 me 页，可见「会员卡」「分销」两行，点击分别进入对应页面。
4. 微信小程序编译不受影响（测试登录 UI 和 `.env.development` 均不进入小程序包）。

## 提交信息

```text
feat(miniprogram): me页补会员卡/分销入口，H5支持测试账号登录
```
