<script setup lang="ts">
import type { IAddress } from '@/api/shop'

withDefaults(defineProps<{
  address?: IAddress | null
}>(), {
  address: null,
})

const emit = defineEmits<{ (e: 'choose'): void }>()
</script>

<template>
  <view class="addr-section" @click="emit('choose')">
    <view v-if="address" class="addr-card">
      <view class="addr-info">
        <view class="addr-line">
          <text class="addr-name">{{ address.name }}</text>
          <text class="addr-mobile">{{ address.mobile }}</text>
        </view>
        <text class="addr-detail">{{ address.region }}{{ address.detail }}</text>
      </view>
      <text class="addr-arrow">›</text>
    </view>
    <view v-else class="addr-empty">
      <text class="addr-empty-text">{{ $t('app.chooseAddress') }}</text>
      <text class="addr-arrow">›</text>
    </view>
  </view>
</template>

<style scoped lang="scss">
.addr-section {
  margin: 16rpx;
  padding: 24rpx;
  background-color: #ffffff;
  border-radius: 12px;
}
.addr-card {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
}
.addr-info {
  display: flex;
  flex-direction: column;
  flex: 1;
}
.addr-line {
  display: flex;
  flex-direction: row;
  align-items: center;
}
.addr-name {
  font-size: 16px;
  color: #1e293b;
  font-weight: 700;
}
.addr-mobile {
  margin-left: 16rpx;
  font-size: 14px;
  color: #64748b;
}
.addr-detail {
  margin-top: 8rpx;
  font-size: 13px;
  color: #475569;
}
.addr-arrow {
  font-size: 14px;
  color: #94a3b8;
}
.addr-empty {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
}
.addr-empty-text {
  font-size: 14px;
  color: #94a3b8;
}
</style>
