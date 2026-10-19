<script setup lang="ts">
import { fenToYuan } from '@/utils/format'

export interface ICartItemView {
  cartId: number
  productId: number
  skuId: number
  quantity: number
  name: string
  image: string
  price: number
  checked: boolean
}

defineProps<{
  item: ICartItemView
}>()

const emit = defineEmits<{
  (e: 'toggle'): void
  (e: 'inc'): void
  (e: 'dec'): void
}>()
</script>

<template>
  <view class="cart-item">
    <view class="check" :class="item.checked ? 'check-on' : ''" @click="emit('toggle')">
      <text v-if="item.checked" class="check-text">✓</text>
    </view>
    <image class="goods-img" :src="item.image" />
    <view class="goods-info">
      <text class="goods-name">{{ item.name }}</text>
      <text class="goods-price">¥{{ fenToYuan(item.price) }}</text>
      <view class="qty-row">
        <view class="qty-btn" @click="emit('dec')">
          <text class="qty-btn-text">-</text>
        </view>
        <text class="qty-num">{{ item.quantity }}</text>
        <view class="qty-btn" @click="emit('inc')">
          <text class="qty-btn-text">+</text>
        </view>
      </view>
    </view>
  </view>
</template>

<style scoped lang="scss">
.cart-item {
  margin: 16rpx;
  padding: 20rpx;
  background-color: #ffffff;
  border-radius: 12px;
  display: flex;
  flex-direction: row;
  align-items: center;
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
.goods-img {
  width: 140rpx;
  height: 140rpx;
  margin-left: 20rpx;
  border-radius: 8px;
}
.goods-info {
  flex: 1;
  margin-left: 20rpx;
  display: flex;
  flex-direction: column;
}
.goods-name {
  font-size: 14px;
  color: #1e293b;
}
.goods-price {
  margin-top: 8rpx;
  font-size: 16px;
  color: #ef4444;
  font-weight: 700;
}
.qty-row {
  margin-top: 12rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
}
.qty-btn {
  width: 48rpx;
  height: 48rpx;
  border-radius: 8px;
  background-color: #f1f5f9;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.qty-btn-text {
  font-size: 16px;
  color: #334155;
}
.qty-num {
  min-width: 64rpx;
  text-align: center;
  font-size: 14px;
  color: #1e293b;
}
</style>
