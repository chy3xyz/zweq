<script setup lang="ts">
import { fenToYuan } from '@/utils/format'

withDefaults(defineProps<{
  name?: string
  price?: number
  originalPrice?: number
  sales?: number
  stock?: number
  favorited?: boolean
}>(), {
  name: '',
  price: 0,
  originalPrice: 0,
  sales: 0,
  stock: 0,
  favorited: false,
})

const emit = defineEmits<{
  (e: 'toggle-favorite'): void
  (e: 'share'): void
}>()
</script>

<template>
  <view class="info">
    <view class="info-top">
      <text class="name">{{ name }}</text>
      <view class="info-actions">
        <view class="fav-btn" @click="emit('toggle-favorite')">
          <text class="fav-icon" :style="{ color: favorited ? '#f59e0b' : '#94a3b8' }">{{ favorited ? '★' : '☆' }}</text>
        </view>
        <view class="share-btn" @click="emit('share')">
          <text class="share-icon">↗</text>
        </view>
      </view>
    </view>
    <view class="price-row">
      <text class="price">¥{{ fenToYuan(price) }}</text>
      <text v-if="originalPrice > 0" class="origin-price">¥{{ fenToYuan(originalPrice) }}</text>
      <text class="sales">已售 {{ sales }} 件</text>
    </view>
    <text class="stock">{{ $t('app.stock') }} {{ stock }}</text>
    <view class="service">
      <text class="service-item">{{ $t('app.authentic') }}</text>
      <text class="service-dot">·</text>
      <text class="service-item">{{ $t('app.returns7d') }}</text>
      <text class="service-dot">·</text>
      <text class="service-item">{{ $t('app.fastShip') }}</text>
    </view>
  </view>
</template>

<style scoped lang="scss">
.info {
  padding: 24rpx;
  background-color: #ffffff;
  display: flex;
  flex-direction: column;
}
.info-top {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
}
.name {
  font-size: 16px;
  color: #1e293b;
  font-weight: 700;
}
.info-actions {
  display: flex;
  flex-direction: row;
  align-items: center;
}
.fav-btn {
  margin-left: 16rpx;
  padding: 8rpx 12rpx;
}
.fav-icon {
  font-size: 20px;
  line-height: 1;
}
.share-btn {
  margin-left: 8rpx;
  padding: 8rpx 12rpx;
}
.share-icon {
  font-size: 20px;
  color: #475569;
  line-height: 1;
}
.price-row {
  margin-top: 16rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
}
.price {
  font-size: 20px;
  color: #ef4444;
  font-weight: 700;
}
.origin-price {
  margin-left: 12rpx;
  font-size: 13px;
  color: #94a3b8;
  text-decoration: line-through;
}
.sales {
  margin-left: auto;
  font-size: 12px;
  color: #94a3b8;
}
.stock {
  margin-top: 12rpx;
  font-size: 13px;
  color: #64748b;
}
.service {
  margin-top: 12rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
}
.service-item {
  font-size: 12px;
  color: #94a3b8;
}
.service-dot {
  margin: 0 8rpx;
  font-size: 12px;
  color: #cbd5e1;
}
</style>
