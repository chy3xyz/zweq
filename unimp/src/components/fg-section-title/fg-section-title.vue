<script setup lang="ts">
withDefaults(defineProps<{
  title?: string
}>(), {
  title: '',
})
</script>

<template>
  <view class="section-title">
    <text class="section-title-text">{{ title }}</text>
  </view>
</template>

<style scoped lang="scss">
.section-title {
  padding: 16rpx 24rpx 8rpx 24rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
}
.section-title-text {
  font-size: 15px;
  color: #1e293b;
  font-weight: 700;
}
</style>
