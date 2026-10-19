<script setup lang="ts">
withDefaults(defineProps<{
  label?: string
  value?: string
}>(), {
  label: '',
  value: '',
})
</script>

<template>
  <view class="asset-card">
    <text class="asset-label">{{ label }}</text>
    <text class="asset-value">{{ value }}</text>
    <slot />
  </view>
</template>

<style scoped lang="scss">
.asset-card {
  margin: 16rpx;
  padding: 32rpx;
  border-radius: 12px;
  background-image: linear-gradient(135deg, var(--theme-color, #0957de), #1890ff);
  display: flex;
  flex-direction: column;
}
.asset-label {
  font-size: 13px;
  color: rgba(255, 255, 255, 0.85);
}
.asset-value {
  margin-top: 12rpx;
  font-size: 40rpx;
  color: #ffffff;
  font-weight: 700;
}
</style>
