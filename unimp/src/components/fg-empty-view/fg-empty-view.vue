<script setup lang="ts">
withDefaults(defineProps<{
  text?: string
}>(), {
  text: '暂无数据',
})
</script>

<template>
  <view class="empty">
    <text class="empty-text">{{ text }}</text>
  </view>
</template>

<style scoped lang="scss">
.empty {
  padding: 60rpx;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
}
.empty-text {
  font-size: 13px;
  color: #94a3b8;
}
</style>
