<script setup lang="ts">
import { computed, ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import { deleteCart, getProductDetail, listCart, updateCart } from '@/api/shop'
import { useFanStore } from '@/store/fan'
import { fenToYuan } from '@/utils/format'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '购物车',
  },
})

interface ICartItemView {
  cartId: number
  productId: number
  skuId: number
  quantity: number
  name: string
  image: string
  price: number
  checked: boolean
}

const fanStore = useFanStore()
const items = ref<ICartItemView[]>([])
const loggedIn = ref(false)

async function loadCart() {
  if (!fanStore.hasLogin) {
    loggedIn.value = false
    items.value = []
    return
  }
  loggedIn.value = true
  try {
    const cartList = await listCart(fanStore.openid)
    const list: ICartItemView[] = []
    for (const cart of cartList) {
      const detail = await getProductDetail(cart.product_id)
      list.push({
        cartId: cart.id,
        productId: cart.product_id,
        skuId: cart.sku_id,
        quantity: cart.quantity,
        name: detail.product.name,
        image: detail.product.image,
        price: detail.product.price,
        checked: true,
      })
    }
    items.value = list
  }
  catch (err) {
    console.error('loadCart error:', err)
  }
}

const totalPrice = computed(() => {
  let sum = 0
  for (const it of items.value) {
    if (it.checked)
      sum += it.price * it.quantity
  }
  return sum
})

const allChecked = computed(() => {
  if (items.value.length === 0)
    return false
  return items.value.every(it => it.checked)
})

const checkedCount = computed(() => {
  let count = 0
  for (const it of items.value) {
    if (it.checked)
      count += it.quantity
  }
  return count
})

function toggleAll() {
  const target = !allChecked.value
  for (const it of items.value) {
    it.checked = target
  }
}

function goHome() {
  uni.switchTab({ url: '/pages/index/index' })
}

function toggleChecked(it: ICartItemView) {
  it.checked = !it.checked
}

function incQuantity(it: ICartItemView) {
  const q = it.quantity + 1
  updateCart(it.cartId, q).then(() => {
    it.quantity = q
  })
}

function decQuantity(it: ICartItemView) {
  const q = it.quantity - 1
  if (q <= 0) {
    deleteCart(it.cartId).then(() => {
      removeItem(it.cartId)
    })
    return
  }
  updateCart(it.cartId, q).then(() => {
    it.quantity = q
  })
}

function removeItem(cartId: number) {
  items.value = items.value.filter(it => it.cartId !== cartId)
}

function goCheckout() {
  const ids = items.value.filter(it => it.checked).map(it => `${it.cartId}`)
  if (ids.length === 0) {
    uni.showToast({ title: '请选择商品', icon: 'none' })
    return
  }
  uni.navigateTo({ url: `/pages-sub/shop/checkout?cartIds=${ids.join(',')}` })
}

function goLogin() {
  uni.navigateTo({ url: '/pages-sub/auth/login' })
}

onShow(() => {
  loadCart()
})
</script>

<template>
  <view class="page-root">
    <fg-navbar title="购物车" :show-back="false" />

    <view v-if="!loggedIn" class="empty">
      <text class="empty-text">登录后查看购物车</text>
      <view class="login-btn" @click="goLogin">
        <text class="login-btn-text">{{ $t('app.goLogin') }}</text>
      </view>
    </view>

    <view v-else class="body">
      <scroll-view scroll-y class="main">
        <fg-cart-item
          v-for="it in items"
          :key="it.cartId"
          :item="it"
          @toggle="toggleChecked(it)"
          @inc="incQuantity(it)"
          @dec="decQuantity(it)"
        />
        <view v-if="items.length === 0" class="empty">
          <text class="empty-text">{{ $t('app.cartEmpty') }}</text>
          <view class="go-shopping-btn" @click="goHome">
            <text class="go-shopping-text">{{ $t('app.goShopping') }}</text>
          </view>
        </view>
      </scroll-view>

      <view class="footer app-fixed-bar">
        <view class="select-all" @click="toggleAll">
          <view class="check" :class="allChecked ? 'check-on' : ''">
            <text v-if="allChecked" class="check-text">✓</text>
          </view>
          <text class="select-all-text">{{ $t('app.selectAll') }}</text>
        </view>
        <view class="total-area">
          <text class="total-label">{{ $t('app.itemsCount', { n: checkedCount }) }}，{{ $t('app.total') }}</text>
          <text class="total-price">¥{{ fenToYuan(totalPrice) }}</text>
        </view>
        <view class="btn-checkout" @click="goCheckout">
          <text class="btn-checkout-text">{{ $t('app.checkout') }}({{ checkedCount }})</text>
        </view>
      </view>
    </view>
  </view>
</template>

<style scoped lang="scss">
.page-root {
  height: 100vh;
  display: flex;
  flex-direction: column;
}
.body {
  flex: 1;
  display: flex;
  flex-direction: column;
  overflow: hidden;
}
.main {
  flex: 1;
  padding-bottom: 180rpx;
}
.check {
  width: 40rpx;
  height: 40rpx;
  border-radius: 20rpx;
  border-width: 1px;
  border-color: #cbd5e1;
  border-style: solid;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.check-on {
  border-color: #ef4444;
  background-color: #ef4444;
}
.check-text {
  font-size: 12px;
  color: #ffffff;
  font-weight: 700;
}
.empty {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 80rpx;
}
.empty-text {
  font-size: 14px;
  color: #94a3b8;
}
.go-shopping-btn {
  margin-top: 32rpx;
  padding: 16rpx 64rpx;
  border-radius: 40rpx;
  background-color: var(--theme-color, #0957de);
}
.go-shopping-text {
  font-size: 15px;
  color: #ffffff;
  font-weight: 700;
}
.login-btn {
  margin-top: 32rpx;
  padding: 16rpx 64rpx;
  border-radius: 40rpx;
  background-color: #ef4444;
}
.login-btn-text {
  font-size: 15px;
  color: #ffffff;
  font-weight: 700;
}
.footer {
  position: fixed;
  left: 0;
  right: 0;
  bottom: calc(50px + env(safe-area-inset-bottom));
  height: 100rpx;
  padding: 0 24rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
  background-color: #ffffff;
  border-radius: 24rpx 24rpx 0 0;
  box-shadow: 0 -10rpx 30rpx rgba(15, 23, 42, 0.06);
  z-index: 2;
}
.select-all {
  margin-right: 20rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
}
.select-all-text {
  margin-left: 8rpx;
  font-size: 14px;
  color: #1e293b;
}
.total-area {
  flex: 1;
  display: flex;
  flex-direction: row;
  align-items: center;
}
.total-label {
  font-size: 14px;
  color: #1e293b;
}
.total-price {
  font-size: 20px;
  color: #ef4444;
  font-weight: 700;
}
.btn-checkout {
  width: 200rpx;
  height: 72rpx;
  border-radius: 36rpx;
  background-color: #ef4444;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.btn-checkout-text {
  font-size: 15px;
  color: #ffffff;
  font-weight: 700;
}
</style>
