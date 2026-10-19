<script setup lang="ts">
import { computed } from 'vue'
import { t } from '@/i18n'

const props = withDefaults(defineProps<{
  title?: string
  count?: number
}>(), {
  title: '',
  count: 0,
})

const emit = defineEmits<{ (e: 'choose'): void }>()

const value = computed(() => {
  if (props.title !== '')
    return props.title
  if (props.count > 0)
    return `${props.count} 张可用`
  return t('app.noCoupon')
})
</script>

<template>
  <view class="coupon-section" @click="emit('choose')">
    <text class="coupon-label">{{ $t('app.coupon') }}</text>
    <text class="coupon-value">{{ value }}</text>
    <text class="coupon-arrow">›</text>
  </view>
</template>

<style scoped lang="scss">
.coupon-section {
  margin: 16rpx;
  padding: 24rpx;
  background-color: #ffffff;
  border-radius: 12px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
}
.coupon-label {
  font-size: 14px;
  color: #1e293b;
}
.coupon-value {
  flex: 1;
  margin-left: 16rpx;
  font-size: 13px;
  color: #ef4444;
  text-align: right;
}
.coupon-arrow {
  margin-left: 8rpx;
  font-size: 14px;
  color: #94a3b8;
}
</style>
