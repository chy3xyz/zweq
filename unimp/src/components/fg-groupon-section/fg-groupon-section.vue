<script setup lang="ts">
import type { IGroupon } from '@/api/shop'
import { fenToYuan } from '@/utils/format'

withDefaults(defineProps<{
  groupons?: IGroupon[]
}>(), {
  groupons: () => [],
})

const emit = defineEmits<{ (e: 'open-groupon', groupon: IGroupon): void }>()
</script>

<template>
  <view class="groupon-wrap">
    <text class="groupon-title">拼团</text>
    <view v-for="g in groupons" :key="g.id" class="groupon-item">
      <view class="groupon-info">
        <text class="groupon-price">拼团价 ¥{{ fenToYuan(g.group_price) }}</text>
        <text class="groupon-size">{{ g.group_size }} 人团</text>
      </view>
      <view class="groupon-btn" @click="emit('open-groupon', g)">
        <text class="groupon-btn-text">开团</text>
      </view>
    </view>
  </view>
</template>

<style scoped lang="scss">
.groupon-wrap {
  margin-top: 16rpx;
  padding: 24rpx;
  background-color: #ffffff;
  display: flex;
  flex-direction: column;
}
.groupon-title {
  font-size: 15px;
  color: #1e293b;
  font-weight: 700;
}
.groupon-item {
  margin-top: 16rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
}
.groupon-info {
  flex: 1;
  display: flex;
  flex-direction: column;
}
.groupon-price {
  font-size: 16px;
  color: #ef4444;
  font-weight: 700;
}
.groupon-size {
  margin-top: 8rpx;
  font-size: 13px;
  color: #64748b;
}
.groupon-btn {
  padding: 12rpx 32rpx;
  border-radius: 24rpx;
  background-color: var(--theme-color, #0957de);
}
.groupon-btn-text {
  font-size: 14px;
  color: #ffffff;
  font-weight: 700;
}
</style>
