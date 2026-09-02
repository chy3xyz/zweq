# unix 小程序 P0 商城核心闭环 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 打通 unix 小程序从粉丝登录到微信支付的完整商城闭环（登录 → 分类/商品 → 购物车 → 结算 → 下单 → 支付 → 订单）。

**架构：** 新增 `FanStore` 粉丝身份 store 与 `auth.uts`/`shop.uts` API 客户端，替换运营者 email 登录模型；复用现有 `request.uts` 信封解包与 `NavBar`/`z-paging-x` 组件；页面按 TabBar（首页/分类/购物车/我的）+ 分包（`src/sub/shop`）组织。

**技术栈：** uni-app X + UTS + Vue3 Composition API + uview-ultra + lime-request + x-pinia-s。

---

## 全局约定（所有任务遵循）

- 后端根路径：`/api/v1`（`request.uts` 的 `baseURL` 已含域名，函数内路径统一写 `/api/v1/...`）。
- 响应信封 `{ code, msg, data }`；`http.get<T>` 返回的是解包后的 `data`。
- 分页响应结构：`IPaged<T> = { list: T[], total: number, page: number, pageSize: number }`。
- 金额单位「分」；时间单位「秒级时间戳」。
- `account_id`：过渡期从 `src/utils/env.uts` 的 `DEFAULT_ACCOUNT_ID` 读取（单账号写死，后端自动识别就绪后移除）。
- 所有 C 端请求统一带 `Authorization: Bearer <fanToken>`，并在 query/body 中显式携带 `openid`（取自 `FanStore`），兼容 shop 模块「token 优先、body 兜底」的鉴权方式。
- 编辑 `.uts/.uvue` 前调用 `uniapp-x-skill`；每步后跑 `uniappx-syntax-checker`。

---

## 任务 1：FanStore 粉丝身份 + 登录鉴权

**文件：**
- 创建：`src/store/fan.uts`
- 创建：`src/api/auth.uts`
- 修改：`src/store/index.uts`
- 修改：`src/utils/env.uts`
- 修改：`src/router/interceptor.uts`
- 修改：`src/http/request.uts`

### 步骤 1：在 env.uts 增加 account_id 配置

在 `src/utils/env.uts` 顶部（`EnvConfig` 之后）新增：

```uts
/** 过渡期：单账号写死 account_id；后端根据小程序 appid 自动识别就绪后移除 */
export const DEFAULT_ACCOUNT_ID: number = 1
```

### 步骤 2：创建 FanStore

创建 `src/store/fan.uts`：

```uts
import { defineStore, PiniaStoreBase } from '@/uni_modules/x-pinia-s'

export type IFanState = {
  fanToken: string
  openid: string
  nickname: string
  avatar: string
  points: number
}

const defaultFanState: IFanState = {
  fanToken: '',
  openid: '',
  nickname: '',
  avatar: '',
  points: 0,
}

export class FanStore extends PiniaStoreBase {
  state: IFanState = reactive<IFanState>({
    fanToken: '',
    openid: '',
    nickname: '',
    avatar: '',
    points: 0,
  } as IFanState)

  constructor() {
    super()
    this.bindState(this.state)
  }

  override _doReset(): void {
    this.state.fanToken = defaultFanState.fanToken
    this.state.openid = defaultFanState.openid
    this.state.nickname = defaultFanState.nickname
    this.state.avatar = defaultFanState.avatar
    this.state.points = defaultFanState.points
  }

  override _hydrate(_data: UTSJSONObject): void {
    if (_data['fanToken'] != null) this.state.fanToken = _data['fanToken'] as string
    if (_data['openid'] != null) this.state.openid = _data['openid'] as string
    if (_data['nickname'] != null) this.state.nickname = _data['nickname'] as string
    if (_data['avatar'] != null) this.state.avatar = _data['avatar'] as string
    if (_data['points'] != null) this.state.points = _data['points'] as number
  }

  override _serialize(): UTSJSONObject {
    return {
      fanToken: this.state.fanToken,
      openid: this.state.openid,
      nickname: this.state.nickname,
      avatar: this.state.avatar,
      points: this.state.points,
    } as UTSJSONObject
  }

  /** 是否已登录（持有效粉丝 token） */
  hasLogin(): boolean {
    return this.state.fanToken != ''
  }

  setFanToken(token: string): void {
    this.state.fanToken = token
  }

  setOpenid(openid: string): void {
    this.state.openid = openid
  }

  setProfile(nickname: string, avatar: string, points: number): void {
    this.state.nickname = nickname
    this.state.avatar = avatar
    this.state.points = points
  }

  clear(): void {
    this._doReset()
    uni.removeStorageSync('fan')
  }
}

export const useFanStore = defineStore<FanStore>('fan', (): FanStore => new FanStore())
```

### 步骤 3：注册 FanStore 持久化

修改 `src/store/index.uts`：把 `includeStores` 加入 `'fan'`：

```uts
pinia.use(createPersistPlugin({
  keyPrefix: 'pinia:',
  includeStores: ['token', 'user', 'app', 'fan'],
  excludeStores: [] as string[],
  serializer: null,
} as PersistOptions))
```

并在文件尾部追加：

```uts
export * from './fan'
```

### 步骤 4：创建 auth.uts API 客户端

创建 `src/api/auth.uts`：

```uts
import { http } from '../http/request'
import { DEFAULT_ACCOUNT_ID } from '../utils/env'

export type IMiniLoginRes = {
  openid: string
}

export type ICLoginRes = {
  token: string
}

export type IFanProfile = {
  openid: string
  nickname: string
  avatar: string
  points: number
}

/** 微信小程序登录：code → openid */
export function miniLogin(code: string, accountId: number = DEFAULT_ACCOUNT_ID): Promise<IMiniLoginRes> {
  return http.post<IMiniLoginRes>('/api/v1/miniprogram/login', {
    account_id: accountId,
    code: code,
  } as UTSJSONObject)
}

/** C 端登录：openid → fan token */
export function cLogin(openid: string, accountId: number = DEFAULT_ACCOUNT_ID): Promise<ICLoginRes> {
  return http.post<ICLoginRes>('/api/v1/shop/auth/login', {
    account_id: accountId,
    openid: openid,
  } as UTSJSONObject)
}

/** 粉丝资料 */
export function getFanProfile(accountId: number = DEFAULT_ACCOUNT_ID): Promise<IFanProfile> {
  return http.get<IFanProfile>(`/api/v1/app/fan/profile?account_id=${accountId}`)
}
```

### 步骤 5：修改 request.uts —— 自动带 fan token、401 跳粉丝登录页

在 `src/http/request.uts` 请求拦截器内（`config.header` 处理之后、`ignoreAuth` 判断处），把当前运营者 token 逻辑替换为 fan token 逻辑：

```uts
if (!ignoreAuth) {
  const fanStore = useFanStore()
  const token = fanStore.state.fanToken
  if (token == '') {
    throw new Error('[请求错误]：未登录')
  }
  header['Authorization'] = `Bearer ${token}`
}
```

响应拦截器 401 分支：把 `tokenStore.clearToken()` 改为：

```uts
if (statusCode == 401) {
  const fanStore = useFanStore()
  fanStore.clear()
  toLoginPage({ mode: 'reLaunch' } as UTSJSONObject)
}
```

同步修改顶部 import（去掉不再使用的 `useTokenStore`，加入 `useFanStore`）。

### 步骤 6：修改 router/interceptor.uts —— 登录判断改用 FanStore

把 `doIntercept` 中的：

```uts
const tokenStore = useTokenStore()
const hasLogin = tokenStore.hasValidLogin()
```

改为：

```uts
const fanStore = useFanStore()
const hasLogin = fanStore.hasLogin()
```

并在 `src/router/config.uts` 把 `LOGIN_PAGE` 保持为 `/src/sub/auth/login`（该页将复用为粉丝登录页）。

### 步骤 7：验证

运行：
```bash
/Applications/HBuilderX-Alpha.app/Contents/MacOS/cli lsp lint --platform app-android --project /Users/n0x/w4_proj/zigmodu_ws/zweq/unix --file /Users/n0x/w4_proj/zigmodu_ws/zweq/unix/src/store/fan.uts
```
并对 `src/api/auth.uts`、`src/http/request.uts`、`src/router/interceptor.uts` 依次 lint。
预期：无语法错误。

---

## 任务 2：shop API 客户端

**文件：**
- 创建：`src/api/shop.uts`

### 步骤 1：定义类型（完整）

创建 `src/api/shop.uts`，顶部类型定义：

```uts
import { http } from '../http/request'
import { DEFAULT_ACCOUNT_ID } from '../utils/env'

export type IPaged<T> = {
  list: T[]
  total: number
  page: number
  pageSize: number
}

export type ICategory = {
  id: number
  account_id: number
  name: string
  parent_id: number
  sort: number
}

export type IProduct = {
  id: number
  account_id: number
  category_id: number
  name: string
  image: string
  content: string
  price: number
  original_price: number
  stock: number
  sales: number
  status: number
  created_at: number
}

export type ISku = {
  id: number
  product_id: number
  spec_json: string
  image: string
  price: number
  stock: number
}

export type IProductDetail = {
  product: IProduct
  skus: ISku[]
}

export type ICart = {
  id: number
  openid: string
  product_id: number
  sku_id: number
  quantity: number
  created_at: number
}

export type IAddress = {
  id: number
  openid: string
  name: string
  mobile: string
  region: string
  detail: string
  is_default: number
}

export type IOrder = {
  id: number
  account_id: number
  order_no: string
  openid: string
  total_amount: number
  pay_amount: number
  status: number
  address_json: string
  express_company: string
  express_no: string
  paid_at: number
  created_at: number
}

export type IOrderProduct = {
  id: number
  order_id: number
  product_id: number
  sku_id: number
  name: string
  image: string
  spec_json: string
  price: number
  quantity: number
  created_at: number
}

export type IOrderDetail = {
  order: IOrder
  items: IOrderProduct[]
  commented_order_product_ids: number[]
}

export type IOrderItemInput = {
  product_id: number
  sku_id: number
  quantity: number
}

export type IOrderCreateReq = {
  account_id: number
  openid: string
  address_id: number
  items: IOrderItemInput[]
  coupon_code: string
  client_trade_no: string
  pay_type: string
  pickup_store_id: number
  remark: string
}

export type IPayParams = {
  mode: string
  amount: number
  order_no: string
  payment: IPaymentField
}

export type IPaymentField = {
  timeStamp: string
  nonceStr: string
  package: string
  signType: string
  paySign: string
}
```

### 步骤 2：实现 API 函数（完整）

在 `src/api/shop.uts` 继续追加：

```uts
/** 分类列表（返回数组，非分页） */
export function listCategories(accountId: number = DEFAULT_ACCOUNT_ID): Promise<ICategory[]> {
  return http.get<ICategory[]>(`/api/v1/shop/categories?account_id=${accountId}`)
}

/** 商品列表（分页） */
export function listProducts(
  categoryId: number,
  page: number,
  pageSize: number,
  keyword: string = '',
  accountId: number = DEFAULT_ACCOUNT_ID,
): Promise<IPaged<IProduct>> {
  let query = `account_id=${accountId}&page=${page}&page_size=${pageSize}`
  if (categoryId > 0) query += `&category_id=${categoryId}`
  if (keyword != '') query += `&keyword=${keyword}`
  return http.get<IPaged<IProduct>>(`/api/v1/shop/products?${query}`)
}

/** 商品详情 */
export function getProductDetail(id: number): Promise<IProductDetail> {
  return http.get<IProductDetail>(`/api/v1/shop/products/${id}`)
}

/** 购物车列表 */
export function listCart(openid: string, accountId: number = DEFAULT_ACCOUNT_ID): Promise<ICart[]> {
  return http.get<ICart[]>(`/api/v1/shop/cart?account_id=${accountId}&openid=${openid}`)
}

/** 加入购物车 */
export function addCart(openid: string, productId: number, skuId: number, quantity: number): Promise<UTSJSONObject> {
  return http.post<UTSJSONObject>('/api/v1/shop/cart/add', {
    openid: openid,
    product_id: productId,
    sku_id: skuId,
    quantity: quantity,
  } as UTSJSONObject)
}

/** 更新购物车数量 */
export function updateCart(cartId: number, quantity: number): Promise<UTSJSONObject> {
  return http.put<UTSJSONObject>(`/api/v1/shop/cart/${cartId}`, {
    quantity: quantity,
  } as UTSJSONObject)
}

/** 删除购物车项 */
export function deleteCart(cartId: number): Promise<UTSJSONObject> {
  return http.delete<UTSJSONObject>(`/api/v1/shop/cart/${cartId}`)
}

/** 地址列表 */
export function listAddresses(openid: string, accountId: number = DEFAULT_ACCOUNT_ID): Promise<IAddress[]> {
  return http.get<IAddress[]>(`/api/v1/shop/addresses?account_id=${accountId}&openid=${openid}`)
}

/** 新增地址 */
export function createAddress(addr: {
  openid: string
  name: string
  mobile: string
  region: string
  detail: string
  is_default: number
}): Promise<UTSJSONObject> {
  return http.post<UTSJSONObject>('/api/v1/shop/addresses', addr as UTSJSONObject)
}

/** 下单 */
export function createOrder(req: IOrderCreateReq): Promise<{ id: number }> {
  return http.post<{ id: number }>('/api/v1/shop/orders', req as UTSJSONObject)
}

/** 订单列表（分页） */
export function listOrders(
  openid: string,
  page: number,
  pageSize: number,
  status: number = -1,
  accountId: number = DEFAULT_ACCOUNT_ID,
): Promise<IPaged<IOrder>> {
  let query = `account_id=${accountId}&page=${page}&page_size=${pageSize}&status=${status}`
  if (openid != '') query += `&openid=${openid}`
  return http.get<IPaged<IOrder>>(`/api/v1/shop/orders?${query}`)
}

/** 订单详情 */
export function getOrderDetail(id: number): Promise<IOrderDetail> {
  return http.get<IOrderDetail>(`/api/v1/shop/orders/${id}`)
}

/** 支付参数（mock 或 wxpay_v3） */
export function getOrderPayParams(id: number): Promise<IPayParams> {
  return http.get<IPayParams>(`/api/v1/shop/orders/${id}/pay-params`)
}

/** 支付完成确认（mock 模式用） */
export function payComplete(id: number): Promise<UTSJSONObject> {
  return http.post<UTSJSONObject>(`/api/v1/shop/orders/${id}/pay-complete`, {} as UTSJSONObject)
}

/** 取消订单 */
export function cancelOrder(id: number): Promise<UTSJSONObject> {
  return http.post<UTSJSONObject>(`/api/v1/shop/orders/${id}/cancel`, {} as UTSJSONObject)
}

/** 确认收货 */
export function confirmOrder(id: number): Promise<UTSJSONObject> {
  return http.post<UTSJSONObject>(`/api/v1/shop/orders/${id}/confirm`, {} as UTSJSONObject)
}
```

### 步骤 2：验证

对 `src/api/shop.uts` 运行 `uniappx-syntax-checker`，预期无错误。

---

## 任务 3：登录页改造（粉丝登录）

**文件：**
- 修改：`src/sub/auth/login.uvue`

### 步骤 1：改写登录页为粉丝登录

将 `src/sub/auth/login.uvue` 的 `doLogin` 逻辑改为粉丝登录流程（保留 `redirectAfterLogin` 跳转函数不变）：

```uts
import { useFanStore } from '../../store'
import { miniLogin, cLogin } from '../../api/auth'

const fanStore = useFanStore()

async function doLogin() {
  if (fanStore.hasLogin()) {
    redirectAfterLogin()
    return
  }

  // 微信小程序：uni.login 拿 code
  uni.login({
    provider: 'weixin',
    success: async (res) => {
      const code = res.code as string
      // 1. code → openid
      const miniRes = await miniLogin(code)
      fanStore.setOpenid(miniRes.openid)
      // 2. openid → fan token
      const loginRes = await cLogin(miniRes.openid)
      fanStore.setFanToken(loginRes.token)

      uni.showToast({ title: '登录成功', icon: 'success' })
      setTimeout(() => {
        redirectAfterLogin()
      }, 800)
    },
    fail: () => {
      uni.showToast({ title: '微信登录失败', icon: 'none' })
    },
  })
}
```

删除原 `tokenStore.setSingleToken`、`userStore.setUserInfo` 及 `ISingleTokenRes/IUserInfo` 相关 import。

### 步骤 2：验证

对 `src/sub/auth/login.uvue` 运行语法校验，预期无错误。

---

## 任务 4：分类页（TabBar 第 2 项）

**文件：**
- 创建：`src/pages/category/category.uvue`
- 修改：`pages.json`
- 修改：`src/tabbar/config.uts`

### 步骤 1：注册 TabBar

修改 `pages.json`：在 `pages` 数组加入 `src/pages/category/category`（`navigationStyle: custom`），并在 `tabBar.list` 的「首页」与「AI」之间加入 `{ "pagePath": "src/pages/category/category", "text": "分类" }`。

修改 `src/tabbar/config.uts`：在 `customTabbarList` 数组对应位置插入分类项（`iconType`/`icon`/`iconActive` 复用现有图标字段，可先复用首页图标）。

### 步骤 2：创建分类页

创建 `src/pages/category/category.uvue`：左侧分类列表 + 右侧商品网格。左侧点击分类加载对应商品（`listProducts(categoryId, 1, 20)`）。

模板骨架（遵循 uni-app X 规范：`flex-direction` 显式声明、`<scroll-view>` 包裹、class 选择器、文字样式放 `<text>`）：

```vue
<template>
  <view class="page flex-col">
    <NavBar title="分类" :show-back="false" />
    <view class="body flex-row">
      <scroll-view scroll-y="true" class="side">
        <view
          v-for="c in categories"
          :key="c.id"
          class="side-item"
          :class="c.id == activeId ? 'side-item-active' : ''"
          @click="onPick(c)"
        >
          <text class="side-text">{{ c.name }}</text>
        </view>
      </scroll-view>
      <scroll-view scroll-y="true" class="main">
        <view v-for="p in products" :key="p.id" class="goods-card flex-row" @click="goDetail(p)">
          <image class="goods-img" :src="p.image" />
          <view class="goods-info flex-col">
            <text class="goods-name">{{ p.name }}</text>
            <text class="goods-price">¥{{ fenToYuan(p.price) }}</text>
          </view>
        </view>
      </scroll-view>
    </view>
  </view>
</template>
```

`<script setup lang="uts">` 逻辑：

```uts
import { ref } from 'vue'
import { listCategories, listProducts, ICategory, IProduct } from '@/src/api/shop'
import { fenToYuan } from '@/src/utils/format'

const categories = ref<ICategory[]>([])
const products = ref<IProduct[]>([])
const activeId = ref<number>(0)

async function loadCategories() {
  categories.value = await listCategories()
  if (categories.value.length > 0) {
    onPick(categories.value[0])
  }
}

async function onPick(c: ICategory) {
  activeId.value = c.id
  const res = await listProducts(c.id, 1, 20)
  products.value = res.list
}

function goDetail(p: IProduct) {
  uni.navigateTo({ url: `/src/sub/shop/product-detail/product-detail?id=${p.id}` })
}

onMounted(() => {
  loadCategories()
})
```

### 步骤 3：验证

`uniappx-syntax-checker` 校验 `category.uvue`，HBuilderX 编译 mp-weixin 确认 TabBar 正常显示 4 项。

---

## 任务 5：商品详情页

**文件：**
- 创建：`src/sub/shop/product-detail/product-detail.uvue`
- 修改：`pages.json`（在 `subPackages` 的 `src/sub` 下注册页面）

### 步骤 1：注册分包页面

在 `pages.json` 的 `subPackages[0].pages` 数组加入 `{ "path": "shop/product-detail/product-detail", "style": { "navigationStyle": "custom" } }`。

### 步骤 2：创建商品详情页

创建 `src/sub/shop/product-detail/product-detail.uvue`：

- `onLoad(options)` 取 `id`，调 `getProductDetail(id)` 得到 `{ product, skus }`。
- 展示商品图、名称、价格（`fenToYuan`）、库存、内容。
- SKU 选择：若无 sku 直接用商品价；若有 sku 用简单弹层选择（P0 可先取第一个 sku）。
- 「加入购物车」按钮调 `addCart(openid, productId, skuId, 1)`；「立即购买」跳结算页。

关键逻辑（`<script setup lang="uts">`）：

```uts
import { ref } from 'vue'
import { getProductDetail, IProductDetail } from '@/src/api/shop'
import { useFanStore } from '@/src/store'

const fanStore = useFanStore()
const detail = ref<IProductDetail | null>(null)
const productId = ref<number>(0)

onLoad((options) => {
  productId.value = parseInt(options['id'] as string)
  load()
})

async function load() {
  detail.value = await getProductDetail(productId.value)
}

async function addToCart() {
  if (!fanStore.hasLogin()) {
    uni.navigateTo({ url: '/src/sub/auth/login' })
    return
  }
  const p = detail.value
  if (p == null) return
  const skuId = p.skus.length > 0 ? p.skus[0].id : 0
  await addCart(fanStore.state.openid, p.product.id, skuId, 1)
  uni.showToast({ title: '已加入购物车', icon: 'success' })
}
```

### 步骤 3：验证

语法校验通过；HBuilderX 编译 mp-weixin 通过。

---

## 任务 6：购物车页（TabBar 第 3 项）

**文件：**
- 创建：`src/pages/cart/cart.uvue`
- 修改：`pages.json`、`src/tabbar/config.uts`

### 步骤 1：注册 TabBar

`pages.json` 的 `pages` 加入 `src/pages/cart/cart`；`tabBar.list` 加入 `{ "pagePath": "src/pages/cart/cart", "text": "购物车" }`。`tabbar/config.uts` 同步插入。

### 步骤 2：创建购物车页

创建 `src/pages/cart/cart.uvue`：

- `onShow` 时若已登录调 `listCart(openid)` 加载；未登录显示「去登录」占位。
- 列表项：商品图、名称、单价、数量增减（`updateCart`）、删除（`deleteCart`）、勾选。
- 底部合计（选中项金额，`fenToYuan`）+「去结算」按钮跳 `checkout`（把选中的 cart id 以参数传递）。

关键逻辑片段：

```uts
async function loadCart() {
  if (!fanStore.hasLogin()) {
    cartList.value = []
    return
  }
  cartList.value = await listCart(fanStore.state.openid)
}

async function changeQty(item: ICart, delta: number) {
  const q = item.quantity + delta
  if (q <= 0) {
    await deleteCart(item.id)
  } else {
    await updateCart(item.id, q)
  }
  loadCart()
}
```

### 步骤 3：验证

语法校验 + 编译验证通过。

---

## 任务 7：地址管理 + 结算下单

**文件：**
- 创建：`src/sub/shop/address-list/address-list.uvue`
- 创建：`src/sub/shop/address-edit/address-edit.uvue`
- 创建：`src/sub/shop/checkout/checkout.uvue`
- 修改：`pages.json`

### 步骤 1：注册页面

`subPackages[0].pages` 加入 `shop/address-list/address-list`、`shop/address-edit/address-edit`、`shop/checkout/checkout`。

### 步骤 2：地址列表页

`address-list.uvue`：`listAddresses(openid)` 列表展示；右上「新增」跳 `address-edit`；选中某地址返回结算页（`uni.$emit` 或事件通道回传 `id`）。

### 步骤 3：地址编辑页

`address-edit.uvue`：表单（姓名/手机/区域/详细地址/默认开关），提交调 `createAddress`，成功返回。

### 步骤 4：结算页

`checkout.uvue`：

- `onLoad` 接收购物车勾选项（`cartIds` 或商品快照参数）。
- 展示商品清单、选择收货地址（跳 `address-list` 选地址）、备注。
- 提交调 `createOrder`：

```uts
import { createOrder, IOrderCreateReq } from '@/src/api/shop'

async function submit() {
  const req: IOrderCreateReq = {
    account_id: DEFAULT_ACCOUNT_ID,
    openid: fanStore.state.openid,
    address_id: selectedAddressId.value,
    items: items.value,  // IOrderItemInput[]：从购物车勾选项构造
    coupon_code: '',
    client_trade_no: '',
    pay_type: 'wxpay',
    pickup_store_id: 0,
    remark: remark.value,
  }
  const res = await createOrder(req)
  // 下单成功 → 跳支付
  uni.navigateTo({ url: `/src/sub/shop/order-detail/order-detail?id=${res.id}&pay=1` })
}
```

### 步骤 5：验证

语法校验 + 编译验证通过。

---

## 任务 8：支付 + 订单列表/详情

**文件：**
- 创建：`src/sub/shop/order-list/order-list.uvue`
- 创建：`src/sub/shop/order-detail/order-detail.uvue`
- 修改：`pages.json`

### 步骤 1：注册页面

`subPackages[0].pages` 加入 `shop/order-list/order-list`、`shop/order-detail/order-detail`。

### 步骤 2：支付逻辑（在 order-detail 内）

`order-detail.uvue` 加载 `getOrderDetail(id)` 展示订单 + 商品清单。若 `options.pay == '1'` 且订单 `status == 0`，调 `getOrderPayParams(id)`：

```uts
import { getOrderPayParams, payComplete } from '@/src/api/shop'

async function pay() {
  const params = await getOrderPayParams(orderId.value)
  if (params.mode == 'wxpay_v3') {
    uni.requestPayment({
      provider: 'wxpay',
      timeStamp: params.payment.timeStamp,
      nonceStr: params.payment.nonceStr,
      package: params.payment.package,
      signType: params.payment.signType,
      paySign: params.payment.paySign,
      success: () => { uni.showToast({ title: '支付成功', icon: 'success' }); load() },
      fail: () => { uni.showToast({ title: '支付取消', icon: 'none' }) },
    })
  } else {
    // mock 模式：直接模拟完成
    await payComplete(orderId.value)
    uni.showToast({ title: '支付成功（mock）', icon: 'success' })
    load()
  }
}
```

### 步骤 3：订单列表页

`order-list.uvue`：`listOrders(openid, page, 20, status)`，用 `z-paging-x` 上拉分页；顶部状态 Tab（全部/待支付/待收货/已完成，status 映射见后端约定，P0 先做「全部」）。点击项跳 `order-detail`。

### 步骤 4：验证

语法校验 + 编译验证通过；真机联调：mock 支付下单→支付→订单状态流转。

---

## 任务 9：首页改造

**文件：**
- 修改：`src/pages/index/index.uvue`

### 步骤 1：接入真实数据与登录态

- 把 `onShow` 中的 `tokenStore/userStore` 逻辑替换为 `FanStore`：`loggedIn.value = fanStore.hasLogin()`，昵称/头像从 `fanStore.state` 读取。
- 「场景应用」宫格保留，但每个宫格跳转目标改为对应分包页（P1 实现页面，P0 先跳占位提示或详情页）。P0 阶段：宫格仅保留入口，点击 `uni.showToast` 提示「敬请期待」。
- 首页顶部加入「商品推荐」区：`listProducts(0, 1, 6)` 展示 6 个商品，点击跳商品详情。

### 步骤 2：验证

语法校验 + 编译验证通过。

---

## 任务 10：全链路联调与收尾

**文件：** 无新增（可能微调上述文件）

### 步骤 1：全链路验证清单

1. `uniappx-syntax-checker` 全量校验改动文件。
2. HBuilderX 编译 `mp-weixin` 通过。
3. 后端 `zig build run` 启动，`web` 管理后台配置好商品/分类/账号（联调前置）。
4. 微信开发者工具走通：登录 → 首页商品 → 分类 → 详情加购 → 购物车 → 结算选地址 → 下单 → mock 支付 → 订单列表/详情。

### 步骤 2：提交（由用户决定是否执行）

```bash
git add -A
git commit -m "feat(miniprogram): P0 商城核心闭环（登录/商品/购物车/下单/支付/订单）"
```

---

## 自检记录

- **规格覆盖度**：P0 范围（登录/分类/商品/购物车/结算/下单/支付/订单）全部覆盖于任务 1-9。`account_id` 兜底（任务 1 步骤 1）覆盖。营销/场景（P1/P2）不在本计划范围，符合「先 P0」决策。
- **类型一致性**：`IProduct/ICart/IAddress/IOrder/IPaged` 等类型在 `shop.uts` 统一定义，各页面 `import` 复用，无重复定义；`openid/account_id` 统一从 `FanStore`/`DEFAULT_ACCOUNT_ID` 取。
- **占位符**：无 TODO/待定；`DEFAULT_ACCOUNT_ID` 默认值 1 为联调前需按环境确认的显式常量（非占位符）。
