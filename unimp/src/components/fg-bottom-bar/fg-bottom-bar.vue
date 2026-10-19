<script setup lang="ts">
import { fenToYuan } from '@/utils/format'

withDefaults(defineProps<{
  price: number
  originalPrice?: number
}>(), {
  originalPrice: 0,
})

const emit = defineEmits<{
  (e: 'add-cart'): void
  (e: 'buy-now'): void
  (e: 'service'): void
}>()
</script>

<template>
  <view class="footer app-fixed-bar">
    <view class="footer-side">
      <text class="footer-price">¥{{ fenToYuan(price) }}</text>
      <text v-if="originalPrice > 0" class="footer-origin">¥{{ fenToYuan(originalPrice) }}</text>
    </view>
    <view class="footer-service" @click="emit('service')">
      <text class="footer-service-icon">💬</text>
      <text class="footer-service-text">{{ $t('app.customerService') }}</text>
    </view>
    <view class="btn-cart" @click="emit('add-cart')">
      <text class="btn-text">{{ $t('app.addCart') }}</text>
    </view>
    <view class="btn-buy" @click="emit('buy-now')">
      <text class="btn-text">{{ $t('app.buyNow') }}</text>
    </view>
  </view>
</template>

<style scoped lang="scss">
.footer {
  position: fixed;
  left: 0;
  right: 0;
  bottom: 0;
  padding: 16rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
  background-color: #ffffff;
  border-radius: 24rpx 24rpx 0 0;
  box-shadow: 0 -10rpx 30rpx rgba(15, 23, 42, 0.06);
  z-index: 100;
}
.footer-side {
  min-width: 150rpx;
  display: flex;
  flex-direction: column;
  justify-content: center;
}
.footer-price {
  font-size: 18px;
  color: #ef4444;
  font-weight: 700;
}
.footer-origin {
  margin-top: 4rpx;
  font-size: 11px;
  color: #94a3b8;
  text-decoration: line-through;
}
.footer-service {
  display: flex;
  flex-direction: column;
  align-items: center;
  margin: 0 8rpx;
}
.footer-service-icon {
  font-size: 22px;
}
.footer-service-text {
  margin-top: 2rpx;
  font-size: 10px;
  color: #64748b;
}
.btn-cart {
  flex: 1;
  height: 80rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  border-radius: 40rpx;
  background-color: #f97316;
}
.btn-buy {
  flex: 1;
  height: 80rpx;
  margin-left: 16rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  border-radius: 40rpx;
  background-color: var(--theme-color, #0957de);
}
.btn-text {
  font-size: 15px;
  color: #ffffff;
  font-weight: 700;
}
</style>
