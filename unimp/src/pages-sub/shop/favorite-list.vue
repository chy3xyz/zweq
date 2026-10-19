<script setup lang="ts">
import { ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import type { IProduct } from '@/api/shop'
import { getProductDetail, listFavorites } from '@/api/shop'
import { useFanStore } from '@/store/fan'
import { fenToYuan } from '@/utils/format'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '我的收藏',
  },
})

const fanStore = useFanStore()
const products = ref<IProduct[]>([])

async function load() {
  if (!fanStore.hasLogin) {
    uni.navigateTo({ url: '/pages-sub/auth/login' })
    return
  }
  try {
    const favs = await listFavorites(fanStore.openid)
    const list: IProduct[] = []
    for (const fav of favs) {
      const detail = await getProductDetail(fav.product_id)
      list.push(detail.product)
    }
    products.value = list
  }
  catch {
    products.value = []
  }
}

function goDetail(product: IProduct) {
  uni.navigateTo({ url: `/pages-sub/shop/product-detail?id=${product.id}` })
}

onShow(() => {
  load()
})
</script>

<template>
  <view class="page">
    <fg-navbar title="我的收藏" />

    <scroll-view scroll-y class="list">
      <view v-for="p in products" :key="p.id" class="goods-card" @click="goDetail(p)">
        <image class="goods-img" :src="p.image" mode="aspectFill" />
        <view class="goods-info">
          <text class="goods-name">{{ p.name }}</text>
          <text class="goods-price">¥{{ fenToYuan(p.price) }}</text>
        </view>
      </view>
      <view v-if="products.length === 0" class="empty">
        <text class="empty-text">还没有收藏商品</text>
      </view>
    </scroll-view>
  </view>
</template>

<style scoped lang="scss">
.page {
  height: 100vh;
  display: flex;
  flex-direction: column;
  background-color: #f8f8f8;
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
