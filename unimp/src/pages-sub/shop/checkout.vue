<script setup lang="ts">
import { computed, ref } from 'vue'
import { onLoad, onShow } from '@dcloudio/uni-app'
import type { IAddress, IOrderCreateReq, IOrderItemInput, IProductDetail } from '@/api/shop'
import { createOrder, getProductDetail, listCart } from '@/api/shop'
import { listMyCoupons } from '@/api/marketing'
import { useFanStore } from '@/store/fan'
import { DEFAULT_ACCOUNT_ID } from '@/utils/env'
import { fenToYuan } from '@/utils/format'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '确认订单',
  },
})

interface ICheckoutItemView {
  productId: number
  skuId: number
  quantity: number
  name: string
  image: string
  price: number
}

interface ICouponOption {
  code: string
  title: string
  amount: number
  min_amount: number
}

const fanStore = useFanStore()
const items = ref<IOrderItemInput[]>([])
const displayItems = ref<ICheckoutItemView[]>([])
const selectedAddress = ref<IAddress | null>(null)
const remark = ref('')
const coupons = ref<ICouponOption[]>([])
const selectedCoupon = ref<ICouponOption | null>(null)
const couponCode = ref('')

onLoad((options) => {
  if (!fanStore.hasLogin) {
    uni.navigateTo({ url: '/pages-sub/auth/login' })
    return
  }
  const query = options as Record<string, string> | undefined
  if (!query)
    return
  if (query.cartIds) {
    loadFromCart(query.cartIds)
  }
  else if (query.productId) {
    const skuId = query.skuId ? Number.parseInt(query.skuId) : 0
    const quantity = query.quantity ? Number.parseInt(query.quantity) : 1
    loadBuyNow(Number.parseInt(query.productId), skuId, quantity)
  }
})

onShow(() => {
  loadSelectedAddress()
  loadCoupons()
})

function resolvePrice(detail: IProductDetail, skuId: number): number {
  return detail.skus.find(s => s.id === skuId)?.price ?? detail.product.price
}

async function loadFromCart(cartIds: string) {
  try {
    const idList = cartIds.split(',').map(v => Number.parseInt(v)).filter(v => !Number.isNaN(v))
    const cartList = await listCart(fanStore.openid)
    const orderItems: IOrderItemInput[] = []
    const viewItems: ICheckoutItemView[] = []
    for (const cart of cartList) {
      if (!idList.includes(cart.id))
        continue
      const detail = await getProductDetail(cart.product_id)
      orderItems.push({
        product_id: cart.product_id,
        sku_id: cart.sku_id,
        quantity: cart.quantity,
      })
      viewItems.push({
        productId: cart.product_id,
        skuId: cart.sku_id,
        quantity: cart.quantity,
        name: detail.product.name,
        image: detail.product.image,
        price: resolvePrice(detail, cart.sku_id),
      })
    }
    items.value = orderItems
    displayItems.value = viewItems
  }
  catch (err) {
    console.error('loadFromCart error:', err)
  }
}

async function loadBuyNow(productId: number, skuId: number, quantity: number) {
  try {
    items.value = [{ product_id: productId, sku_id: skuId, quantity }]
    const detail = await getProductDetail(productId)
    displayItems.value = [{
      productId,
      skuId,
      quantity,
      name: detail.product.name,
      image: detail.product.image,
      price: resolvePrice(detail, skuId),
    }]
  }
  catch (err) {
    console.error('loadBuyNow error:', err)
  }
}

const totalPrice = computed(() => displayItems.value.reduce((sum, it) => sum + it.price * it.quantity, 0))
const totalCount = computed(() => displayItems.value.reduce((sum, it) => sum + it.quantity, 0))

function loadSelectedAddress() {
  const saved = uni.getStorageSync('selectedAddress')
  if (!saved || typeof saved !== 'string')
    return
  try {
    const addr = JSON.parse(saved) as IAddress
    if (addr)
      selectedAddress.value = addr
  }
  catch {
    // 存储内容损坏时忽略
  }
}

function goChooseAddress() {
  uni.navigateTo({ url: '/pages-sub/shop/address-list' })
}

function loadCoupons() {
  if (!fanStore.hasLogin)
    return
  listMyCoupons(1, 50).then((my) => {
    // 只展示未使用券；门槛由后端在提交时校验（onShow 时商品清单可能尚未加载完）
    coupons.value = my.list
      .filter(mc => mc.status === 'unused')
      .map(mc => ({
        code: mc.code,
        title: mc.title !== '' ? mc.title : '优惠券',
        amount: mc.amount,
        min_amount: mc.min_amount,
      }))
  }).catch(() => {
    coupons.value = []
  })
}

function chooseCoupon() {
  if (coupons.value.length === 0) {
    uni.showToast({ title: '暂无可用优惠券', icon: 'none' })
    return
  }
  const itemList = coupons.value.map((c) => {
    const amt = c.amount > 0 ? `减${fenToYuan(c.amount)}` : ''
    return `${c.title}${amt}`
  })
  uni.showActionSheet({
    itemList,
    success: (res) => {
      const option = coupons.value[res.tapIndex]
      selectedCoupon.value = option
      couponCode.value = option.code
    },
  })
}

function submitOrder() {
  if (items.value.length === 0) {
    uni.showToast({ title: '订单为空', icon: 'none' })
    return
  }
  const addr = selectedAddress.value
  if (!addr) {
    uni.showToast({ title: '请选择收货地址', icon: 'none' })
    return
  }
  const req: IOrderCreateReq = {
    account_id: DEFAULT_ACCOUNT_ID,
    openid: fanStore.openid,
    address_id: addr.id,
    items: items.value,
    coupon_code: couponCode.value,
    client_trade_no: '',
    pay_type: 'wxpay',
    pickup_store_id: 0,
    remark: remark.value,
  }
  createOrder(req).then((res) => {
    uni.removeStorageSync('selectedAddress')
    uni.redirectTo({ url: `/pages-sub/shop/order-detail?id=${res.id}&pay=1` })
  }).catch(() => {})
}
</script>

<template>
  <view class="page-root">
    <fg-navbar :title="$t('app.confirmOrder')" />

    <scroll-view scroll-y class="main">
      <fg-address-card :address="selectedAddress" @choose="goChooseAddress" />
      <fg-goods-list :items="displayItems" />
      <fg-coupon-bar :title="selectedCoupon ? selectedCoupon.title : ''" :count="coupons.length" @choose="chooseCoupon" />

      <view class="remark-section">
        <text class="remark-label">{{ $t('app.remark') }}</text>
        <input
          v-model="remark"
          class="remark-input"
          :placeholder="$t('app.remarkPlaceholder')"
          placeholder-style="color: #cbd5e1"
        >
      </view>
    </scroll-view>

    <fg-total-bar :price="totalPrice" :count="totalCount" @submit="submitOrder" />
  </view>
</template>

<style scoped lang="scss">
.page-root {
  height: 100vh;
  display: flex;
  flex-direction: column;
  background-color: #f8f8f8;
}
.main {
  flex: 1;
  padding-bottom: 20rpx;
}
.remark-section {
  margin: 0 16rpx;
  padding: 24rpx;
  background-color: #ffffff;
  border-radius: 12px;
  display: flex;
  flex-direction: row;
  align-items: center;
}
.remark-label {
  font-size: 14px;
  color: #1e293b;
}
.remark-input {
  flex: 1;
  margin-left: 16rpx;
  font-size: 14px;
  color: #1e293b;
}
</style>
