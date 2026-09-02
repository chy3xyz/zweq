# unix me 页入口 + H5 测试登录 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `unix/` 子仓补齐 me 页「会员卡」「分销」入口，并为 H5 平台实现测试账号登录能力，同时清理无意义的 mock 示例。

**Architecture:** 保持现有页面结构不变，通过条件编译仅在 H5/App 包注入测试登录 UI；H5 开发环境通过 `.env.development` 指向本地后端 8000 端口；登录复用已有的 `cLogin(openid)` 与 `FanStore` 状态管理。

**Tech Stack:** uni-app X (UTS + Vue3 + uview-ultra), Vite, lime-request, x-pinia-s

## Global Constraints

- 仅在 `unix/` 子仓内修改代码。
- 测试登录 UI 必须包裹在 `#ifndef MP-WEIXIN` 条件编译中，不得进入小程序包。
- H5 联调必须指向 `http://localhost:8000`。
- 视觉风格与现有 me 页入口保持一致。
- 提交信息格式：`feat(miniprogram): ...` 中文描述。

---

## File Structure

| 文件 | 动作 | 说明 |
| --- | --- | --- |
| `unix/src/sub/auth/login.uvue` | 修改 | 在 `#ifndef MP-WEIXIN` 分支添加 openid 输入框和测试登录按钮 |
| `unix/src/pages/me/me.uvue` | 修改 | 在「钱包」行下方追加「会员卡」「分销」入口 |
| `unix/src/api/foo.uts` | 删除 | 早期 mock 示例 |
| `unix/.env.development` | 新增 | Vite H5 开发环境 baseURL 指向本地 8000 |

---

### Task 1: H5 测试登录 UI 与逻辑

**Files:**
- Modify: `unix/src/sub/auth/login.uvue`

**Interfaces:**
- Consumes: `cLogin(openid: string): Promise<ICLoginRes>` from `../../api/auth`, `getFanProfile(): Promise<IFanProfile>` from `../../api/auth`, `FanStore.setOpenid/setFanToken/setProfile` from `../../store`。
- Produces: H5 平台下点击「测试账号登录」即可完成登录并跳转。

- [ ] **Step 1: 读取当前 login.uvue 确认结构**

已确认：文件 86 行，`doLogin()` 中 `#ifndef MP-WEIXIN` 分支仅一行 toast。

- [ ] **Step 2: 添加 openid 响应式变量**

在 `<script setup>` 顶部新增：

```uts
const testOpenid = ref<string>(`dev_${Date.now()}`)
```

- [ ] **Step 3: 修改模板，为 H5 渲染测试登录区域**

将 `<template>` 中原来的单一登录按钮替换为平台区分结构：

```vue
<template>
  <view class="flex-1 p-30px items-center">
    <view class="mb-30px">
      <text class="text-20px font-bold text-[#1e293b]">登录页</text>
    </view>

    <!-- #ifdef MP-WEIXIN -->
    <view
      class="w-200px h-44px rounded-8px bg-[var(--theme-color)] flex flex-row items-center justify-center"
      @click="doLogin"
    >
      <text class="text-[#ffffff] text-14px font-bold">微信一键登录</text>
    </view>
    <!-- #endif -->

    <!-- #ifndef MP-WEIXIN -->
    <view class="w-full flex flex-col items-center">
      <input
        v-model="testOpenid"
        class="w-full h-44px px-16px rounded-8px bg-[#f1f5f9] text-14px text-[#1e293b] mb-16px"
        placeholder="请输入测试 openid"
        placeholder-class="text-[#94a3b8]"
      />
      <view
        class="w-full h-44px rounded-8px bg-[var(--theme-color)] flex flex-row items-center justify-center"
        @click="doTestLogin"
      >
        <text class="text-[#ffffff] text-14px font-bold">测试账号登录</text>
      </view>
    </view>
    <!-- #endif -->
  </view>
</template>
```

- [ ] **Step 4: 新增 doTestLogin 方法并复用已有跳转逻辑**

在 `doLogin()` 下方新增：

```uts
function doTestLogin() {
  if (fanStore.hasLogin()) {
    redirectAfterLogin()
    return
  }

  const openid = testOpenid.value.trim()
  if (openid == '') {
    uni.showToast({ title: '请输入 openid', icon: 'none' })
    return
  }

  cLogin(openid).then((loginRes) => {
    fanStore.setOpenid(openid)
    fanStore.setFanToken(loginRes.token)
    uni.showToast({ title: '登录成功', icon: 'success' })
    setTimeout(() => { redirectAfterLogin() }, 800)
    getFanProfile().then((profile) => {
      fanStore.setProfile(profile.nickname, profile.avatar, profile.points)
    }).catch(() => {})
  }).catch(() => {
    uni.showToast({ title: '登录失败', icon: 'none' })
  })
}
```

- [ ] **Step 5: 清理原 #ifndef 分支**

将 `doLogin()` 内 `#ifndef MP-WEIXIN` 分支的 toast 删除，因为模板已按平台拆分。

- [ ] **Step 6: H5 编译验证**

Run:
```bash
cd unix
pnpm build:h5
```
Expected: 构建成功，无新增错误。

- [ ] **Step 7: Commit**

```bash
cd unix
git add src/sub/auth/login.uvue
git commit -m "feat(miniprogram): H5支持测试账号登录"
```

---

### Task 2: me 页补齐「会员卡」「分销」入口

**Files:**
- Modify: `unix/src/pages/me/me.uvue`

**Interfaces:**
- Consumes: 已有 `uni.navigateTo` 与 `fanStore.hasLogin()`。
- Produces: `goMemberCard()` 与 `goDistribution()` 两个无参跳转函数。

- [ ] **Step 1: 在模板「钱包」行下方追加两行**

```vue
<view class="h-48px rounded-8px bg-[#f8fafc] flex flex-row items-center px-16px mb-12px" @click="goMemberCard">
  <text class="text-14px text-[#1e293b]">会员卡</text>
  <text class="flex-1 text-right text-12px text-[#94a3b8]">›</text>
</view>
<view class="h-48px rounded-8px bg-[#f8fafc] flex flex-row items-center px-16px" @click="goDistribution">
  <text class="text-14px text-[#1e293b]">分销</text>
  <text class="flex-1 text-right text-12px text-[#94a3b8]">›</text>
</view>
```

- [ ] **Step 2: 在 script 中新增两个跳转函数**

```uts
// 会员卡
function goMemberCard() {
  uni.navigateTo({ url: '/src/sub/marketing/member-card/member-card' })
}

// 分销
function goDistribution() {
  uni.navigateTo({ url: '/src/sub/marketing/distribution/distribution' })
}
```

- [ ] **Step 3: H5 编译验证**

Run:
```bash
cd unix
pnpm build:h5
```
Expected: 构建成功。

- [ ] **Step 4: Commit**

```bash
cd unix
git add src/pages/me/me.uvue
git commit -m "feat(miniprogram): me页增加会员卡和分销入口"
```

---

### Task 3: H5 开发环境指向本地后端并删除 mock

**Files:**
- Delete: `unix/src/api/foo.uts`
- Create: `unix/.env.development`

**Interfaces:**
- Consumes: Vite 在 H5 模式下读取 `import.meta.env.VITE_SERVER_BASEURL`。
- Produces: H5 `pnpm dev` 默认请求 `http://localhost:8000`。

- [ ] **Step 1: 删除 mock 示例文件**

```bash
cd unix
rm src/api/foo.uts
```

- [ ] **Step 2: 新增 .env.development**

Create `unix/.env.development`:

```env
VITE_SERVER_BASEURL=http://localhost:8000
```

- [ ] **Step 3: 确认本地 8000 后端已运行**

Run:
```bash
lsof -i :8000 | grep LISTEN
```
Expected: 显示 `zweq` 进程监听 8000。

- [ ] **Step 4: Commit**

```bash
cd unix
git add .env.development
git commit -m "feat(miniprogram): H5开发环境指向本地8000并删除mock示例"
```

---

### Task 4: 端到端验证

**Files:**
- 无文件改动，仅验证。

- [ ] **Step 1: 启动 H5 开发服务器**

Run:
```bash
cd unix
pnpm dev
```
Expected: 服务启动在 `http://localhost:9001`。

- [ ] **Step 2: 浏览器访问登录页并完成测试登录**

1. 打开 `http://localhost:9001/src/sub/auth/login`（或从 me 页点击登录进入）。
2. 使用默认 openid 点击「测试账号登录」。
3. Expected: toast「登录成功」并返回上一页；me 页显示「已登录」。

- [ ] **Step 3: 验证 me 页新入口**

1. 在 me 页点击「会员卡」。
2. Expected: 跳转到 `/src/sub/marketing/member-card/member-card` 页面。
3. 返回后点击「分销」。
4. Expected: 跳转到 `/src/sub/marketing/distribution/distribution` 页面。

- [ ] **Step 4: 验证网络请求指向本地 8000**

打开浏览器 DevTools Network，确认 `POST /api/v1/shop/auth/login` 请求 URL 为 `http://localhost:8000/api/v1/shop/auth/login`。

- [ ] **Step 5: 微信小程序编译不受影响**

Run:
```bash
cd unix
pnpm build:mp-weixin
```
Expected: 构建成功，且生成包中不应包含测试登录 UI 与 `.env.development`。

---

## Self-Review

- **Spec coverage:**
  - me 页补入口 → Task 2
  - H5 测试登录 → Task 1
  - `.env.development` 指向本地 8000 → Task 3
  - 删除 `src/api/foo.uts` → Task 3
  - 端到端验证 → Task 4
  无遗漏。
- **Placeholder scan:** 无 TBD/TODO/"later" 等占位。
- **Type consistency:** `cLogin`/`getFanProfile`/`FanStore` 方法名与 spec 及源码一致。
