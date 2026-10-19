<script setup lang="ts">
import { fenToYuan } from '@/utils/format'

withDefaults(defineProps<{
  price?: number
  count?: number
}>(), {
  price: 0,
  count: 0,
})

const emit = defineEmits<{ (e: 'submit'): void }>()
</script>

<template>
  <view class="footer">
    <view class="total-area">
      <text class="total-label">{{ $t('app.itemsCount', { n: count }) }}，{{ $t('app.total') }}</text>
      <text class="total-price">¥{{ fenToYuan(price) }}</text>
    </view>
    <view class="btn-submit" @click="emit('submit')">
      <text class="btn-submit-text">{{ $t('app.submitOrder') }}</text>
    </view>
  </view>
</template>

<style scoped lang="scss">
.footer {
  height: 100rpx;
  padding: 0 24rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
  background-color: #ffffff;
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
.btn-submit {
  width: 200rpx;
  height: 72rpx;
  border-radius: 36rpx;
  background-color: var(--theme-color, #0957de);
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.btn-submit-text {
  font-size: 15px;
  color: #ffffff;
  font-weight: 700;
}
</style>
