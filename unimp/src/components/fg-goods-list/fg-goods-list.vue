<script setup lang="ts">
import { fenToYuan } from '@/utils/format'

export interface IGoodsItem {
  name: string
  image: string
  price: number
  quantity: number
}

withDefaults(defineProps<{
  items?: IGoodsItem[]
}>(), {
  items: () => [],
})
</script>

<template>
  <view class="goods-section">
    <text class="section-title">{{ $t('app.goodsList') }}</text>
    <view v-for="(it, idx) in items" :key="idx" class="goods-item">
      <image class="goods-img" :src="it.image" />
      <view class="goods-info">
        <text class="goods-name">{{ it.name }}</text>
        <view class="goods-bottom">
          <text class="goods-price">¥{{ fenToYuan(it.price) }}</text>
          <text class="goods-qty">x{{ it.quantity }}</text>
        </view>
      </view>
    </view>
    <view v-if="items.length === 0" class="goods-empty">
      <text class="goods-empty-text">{{ $t('app.noResult') }}</text>
    </view>
  </view>
</template>

<style scoped lang="scss">
.goods-section {
  margin: 0 16rpx;
  padding: 24rpx;
  background-color: #ffffff;
  border-radius: 12px;
  display: flex;
  flex-direction: column;
}
.section-title {
  font-size: 15px;
  color: #1e293b;
  font-weight: 700;
}
.goods-item {
  margin-top: 16rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
}
.goods-img {
  width: 120rpx;
  height: 120rpx;
  border-radius: 8px;
}
.goods-info {
  flex: 1;
  margin-left: 20rpx;
  display: flex;
  flex-direction: column;
}
.goods-name {
  font-size: 14px;
  color: #1e293b;
}
.goods-bottom {
  margin-top: 12rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
}
.goods-price {
  font-size: 15px;
  color: #ef4444;
  font-weight: 700;
}
.goods-qty {
  font-size: 13px;
  color: #64748b;
}
.goods-empty {
  margin-top: 16rpx;
  padding: 24rpx;
  display: flex;
  flex-direction: column;
  align-items: center;
}
.goods-empty-text {
  font-size: 13px;
  color: #94a3b8;
}
</style>
