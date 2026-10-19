<script setup lang="ts">
withDefaults(defineProps<{
  margin?: string
}>(), {
  margin: '16rpx',
})
</script>

<template>
  <view class="card" :style="{ margin }">
    <slot />
  </view>
</template>

<style scoped lang="scss">
.card {
  padding: 24rpx;
  background-color: #ffffff;
  border-radius: 12px;
  display: flex;
  flex-direction: column;
}
</style>
