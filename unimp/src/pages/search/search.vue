<script setup lang="ts">
import { ref } from 'vue'
import type { IProduct } from '@/api/shop'
import { listProducts } from '@/api/shop'
import { fenToYuan } from '@/utils/format'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '搜索',
  },
})

const keyword = ref('')
const products = ref<IProduct[]>([])
const searched = ref(false)

const hotKeywords = ['签到', '优惠券', '积分', '秒杀', '会员卡', '大转盘']

function onHotKw(kw: string) {
  keyword.value = kw
  doSearch()
}

function doSearch() {
  const kw = keyword.value.trim()
  if (kw === '')
    return
  searched.value = true
  listProducts(0, 1, 30, kw).then((res) => {
    products.value = res.list
  }).catch(() => {
    products.value = []
  })
}

function goDetail(product: IProduct) {
  uni.navigateTo({ url: `/pages-sub/shop/product-detail?id=${product.id}` })
}
</script>

<template>
  <view class="page">
    <fg-navbar title="搜索" />

    <view class="search-bar">
      <input
        v-model="keyword"
        type="text"
        :placeholder="$t('app.searchPlaceholder')"
        placeholder-style="color: #94a3b8"
        class="search-input"
        confirm-type="search"
        @confirm="doSearch"
      >
      <view class="search-btn" @click="doSearch">
        <text class="search-btn-text">搜索</text>
      </view>
    </view>

    <view v-if="!searched" class="hot-search">
      <text class="hot-title">{{ $t('app.hotSearch') }}</text>
      <view class="hot-tags">
        <text v-for="kw in hotKeywords" :key="kw" class="hot-tag" @click="onHotKw(kw)">{{ kw }}</text>
      </view>
    </view>

    <scroll-view scroll-y class="list">
      <view v-for="p in products" :key="p.id" class="goods-card" @click="goDetail(p)">
        <image class="goods-img" :src="p.image" mode="aspectFill" />
        <view class="goods-info">
          <text class="goods-name">{{ p.name }}</text>
          <text class="goods-price">¥{{ fenToYuan(p.price) }}</text>
        </view>
      </view>
      <view v-if="searched && products.length === 0" class="empty">
        <text class="empty-text">{{ $t('app.noResult') }}</text>
      </view>
    </scroll-view>
  </view>
</template>

<style scoped lang="scss">
.page {
  height: 100vh;
  display: flex;
  flex-direction: column;
}
.search-bar {
  padding: 16rpx 24rpx;
  background-color: #ffffff;
  display: flex;
  flex-direction: row;
  align-items: center;
}
.search-input {
  flex: 1;
  height: 72rpx;
  padding-left: 24rpx;
  border-radius: 36rpx;
  background-color: #f1f5f9;
  font-size: 14px;
  color: #1e293b;
}
.search-btn {
  height: 72rpx;
  margin-left: 16rpx;
  padding: 0 40rpx;
  border-radius: 36rpx;
  background-color: var(--theme-color, #0957de);
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.search-btn-text {
  font-size: 14px;
  color: #ffffff;
  font-weight: 700;
}
.hot-search {
  padding: 24rpx;
}
.hot-title {
  font-size: 14px;
  color: #1e293b;
  font-weight: 700;
}
.hot-tags {
  margin-top: 20rpx;
  display: flex;
  flex-direction: row;
  flex-wrap: wrap;
}
.hot-tag {
  padding: 12rpx 28rpx;
  margin: 0 16rpx 16rpx 0;
  border-radius: 24rpx;
  background-color: #f1f5f9;
  font-size: 13px;
  color: #475569;
}
.list {
  flex: 1;
}
.goods-card {
  margin: 16rpx;
  padding: 20rpx;
  background-color: #ffffff;
  border-radius: 12px;
  display: flex;
  flex-direction: row;
  align-items: center;
}
.goods-img {
  width: 140rpx;
  height: 140rpx;
  border-radius: 8px;
}
.goods-info {
  flex: 1;
  margin-left: 20rpx;
  display: flex;
  flex-direction: column;
  justify-content: center;
}
.goods-name {
  font-size: 14px;
  color: #1e293b;
}
.goods-price {
  margin-top: 12rpx;
  font-size: 16px;
  color: #ef4444;
  font-weight: 700;
}
.empty {
  padding: 80rpx;
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
