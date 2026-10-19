<script setup lang="ts">
import { ref } from 'vue'
import type { ICategory, IProduct } from '@/api/shop'
import { listCategories, listProducts } from '@/api/shop'
import { fenToYuan } from '@/utils/format'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '分类',
  },
})

const categories = ref<ICategory[]>([])
const products = ref<IProduct[]>([])
const activeId = ref(0)

function loadCategories() {
  listCategories().then((list) => {
    categories.value = list
    if (list.length > 0) {
      onPick(list[0])
    }
  }).catch(() => {
    categories.value = []
  })
}

function onPick(category: ICategory) {
  activeId.value = category.id
  listProducts(category.id, 1, 20).then((res) => {
    products.value = res.list
  }).catch(() => {
    products.value = []
  })
}

function goDetail(product: IProduct) {
  uni.navigateTo({ url: `/pages-sub/shop/product-detail?id=${product.id}` })
}

onMounted(() => {
  loadCategories()
})
</script>

<template>
  <view class="page-root">
    <fg-navbar title="分类" :show-back="false" />
    <view class="body">
      <scroll-view scroll-y class="side">
        <view
          v-for="c in categories" :key="c.id"
          class="side-item"
          :class="c.id === activeId ? 'side-item-active' : ''"
          @click="onPick(c)"
        >
          <text :class="c.id === activeId ? 'side-text-active' : 'side-text'">{{ c.name }}</text>
        </view>
      </scroll-view>
      <scroll-view scroll-y class="main">
        <view v-for="p in products" :key="p.id" class="goods-card" @click="goDetail(p)">
          <image class="goods-img" :src="p.image" />
          <view class="goods-info">
            <text class="goods-name">{{ p.name }}</text>
            <text class="goods-price">¥{{ fenToYuan(p.price) }}</text>
          </view>
        </view>
        <view v-if="products.length === 0" class="empty">
          <text class="empty-text">{{ $t('app.noResult') }}</text>
        </view>
      </scroll-view>
    </view>
    <view class="tabbar-holder" />
  </view>
</template>

<style scoped lang="scss">
.page-root {
  height: 100vh;
  display: flex;
  flex-direction: column;
}
.body {
  flex: 1;
  display: flex;
  flex-direction: row;
  align-items: stretch;
  overflow: hidden;
}
.side {
  width: 180rpx;
  height: 100%;
  background-color: #f8fafc;
}
.side-item {
  padding: 24rpx 16rpx;
}
.side-item-active {
  background-color: #ffffff;
  border-left-width: 6rpx;
  border-left-style: solid;
  border-left-color: var(--theme-color, #0957de);
}
.side-text {
  font-size: 14px;
  color: #334155;
}
.side-text-active {
  font-size: 14px;
  color: var(--theme-color, #0957de);
  font-weight: 700;
}
.main {
  flex: 1;
  height: 100%;
  padding: 16rpx 16rpx 180rpx 16rpx;
  box-sizing: border-box;
}
.goods-card {
  padding: 12rpx;
  margin-bottom: 16rpx;
  background-color: #ffffff;
  border-radius: 8px;
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
  margin-left: 16rpx;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}
.goods-name {
  font-size: 14px;
  color: #1e293b;
}
.goods-price {
  font-size: 16px;
  color: #ef4444;
  font-weight: 700;
}
.empty {
  padding: 40rpx;
  display: flex;
  flex-direction: column;
  align-items: center;
}
.empty-text {
  font-size: 13px;
  color: #94a3b8;
}
</style>
