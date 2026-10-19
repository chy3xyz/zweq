<script setup lang="ts">
import type { ISku } from '@/api/shop'

withDefaults(defineProps<{
  skus?: ISku[]
  selectedSkuId?: number
}>(), {
  skus: () => [],
  selectedSkuId: 0,
})

const emit = defineEmits<{ (e: 'select', skuId: number): void }>()
</script>

<template>
  <view class="sku-wrap">
    <text class="sku-title">{{ $t('app.chooseSpec') }}</text>
    <view class="sku-row">
      <view
        v-for="s in skus"
        :key="s.id"
        class="sku-item"
        :class="s.id === selectedSkuId ? 'sku-item-active' : ''"
        @click="emit('select', s.id)"
      >
        <text :class="s.id === selectedSkuId ? 'sku-text-active' : 'sku-text'">{{ s.spec_json }}</text>
      </view>
    </view>
  </view>
</template>

<style scoped lang="scss">
.sku-wrap {
  margin-top: 16rpx;
  padding: 24rpx;
  background-color: #ffffff;
  display: flex;
  flex-direction: column;
}
.sku-title {
  font-size: 14px;
  color: #1e293b;
  font-weight: 700;
}
.sku-row {
  margin-top: 16rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
  flex-wrap: wrap;
}
.sku-item {
  padding: 12rpx 24rpx;
  margin-right: 16rpx;
  margin-bottom: 16rpx;
  border-width: 1px;
  border-color: #e2e8f0;
  border-style: solid;
  border-radius: 8px;
  background-color: #f8fafc;
}
.sku-item-active {
  border-color: var(--theme-color, #0957de);
  background-color: rgba(9, 87, 222, 0.06);
}
.sku-text {
  font-size: 13px;
  color: #334155;
}
.sku-text-active {
  font-size: 13px;
  color: var(--theme-color, #0957de);
}
</style>
