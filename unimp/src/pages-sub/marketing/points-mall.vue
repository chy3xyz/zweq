<script setup lang="ts">
import { ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import { getFanProfile } from '@/api/auth'
import type { IPointsOrder, IPointsProduct } from '@/api/marketing'
import { listPointsOrders, listPointsProducts, redeemPoints } from '@/api/marketing'
import { t } from '@/i18n'
import { useFanStore } from '@/store/fan'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '积分商城',
  },
})

const fanStore = useFanStore()
const myPoints = ref(0)
const products = ref<IPointsProduct[]>([])
const orders = ref<IPointsOrder[]>([])

function load() {
  getFanProfile().then((p) => {
    myPoints.value = p.points
  }).catch(() => {})
  listPointsProducts(1, 20).then((res) => {
    products.value = res.list
  }).catch(() => {})
  listPointsOrders().then((list) => {
    orders.value = list
  }).catch(() => {})
}

function canRedeem(product: IPointsProduct): boolean {
  return myPoints.value >= product.points && product.stock > 0
}

function onRedeem(product: IPointsProduct) {
  if (myPoints.value < product.points) {
    uni.showToast({ title: '积分不足', icon: 'none' })
    return
  }
  if (product.stock <= 0) {
    uni.showToast({ title: '库存不足', icon: 'none' })
    return
  }
  redeemPoints(product.id).then(() => {
    uni.showToast({ title: t('mkt.redeemSuccess'), icon: 'success' })
    load()
  }).catch(() => {})
}

function orderStatusText(status: string): string {
  if (status === 'completed' || status === 'redeemed')
    return t('mkt.redeemCompleted')
  if (status === 'pending')
    return t('mkt.redeemPending')
  if (status === 'cancelled')
    return t('mkt.redeemCancelled')
  return status
}

onShow(() => {
  if (!fanStore.hasLogin) {
    uni.navigateTo({ url: '/pages-sub/auth/login' })
    return
  }
  load()
})
</script>

<template>
  <view class="z-page">
    <fg-navbar :title="$t('mkt.pointsMall')" />
    <scroll-view scroll-y class="z-body">
      <fg-asset-card :label="$t('mkt.myPoints')" :value="`${myPoints}`" />

      <fg-section-title :title="$t('mkt.pointsProducts')" />

      <view v-for="p in products" :key="p.id" class="mx-4 mb-2 flex flex-row items-center justify-between rounded-3 bg-white p-6">
        <view class="flex flex-1 flex-col">
          <text class="text-[15px] text-[#1e293b] font-bold">{{ p.name }}</text>
          <text class="mt-2 text-[14px] text-[#ef4444]">{{ p.points }} 积分</text>
          <text class="mt-1 text-[12px] text-[#94a3b8]">库存 {{ p.stock }}</text>
        </view>
        <view class="rounded-full px-7 py-3" :class="canRedeem(p) ? 'bg-primary' : 'bg-[#cbd5e1]'" @click="onRedeem(p)">
          <text class="text-[14px] text-white">
            {{ p.stock <= 0 ? '已售罄' : (canRedeem(p) ? $t('mkt.redeem') : '积分不足') }}
          </text>
        </view>
      </view>
      <fg-empty-view v-if="products.length === 0" :text="$t('mkt.noProducts')" />

      <fg-section-title :title="$t('mkt.myRedeemRecords')" />

      <view v-for="o in orders" :key="o.id" class="mx-4 mb-2 flex flex-row items-center justify-between rounded-3 bg-white p-6">
        <view class="flex flex-1 flex-col">
          <text class="text-[14px] text-[#1e293b]">{{ o.product_name }}</text>
          <text class="mt-1 text-[12px] text-[#94a3b8]">{{ o.points_spent }} 积分</text>
        </view>
        <text class="text-[13px] text-[#ef4444]">{{ orderStatusText(o.status) }}</text>
      </view>
      <fg-empty-view v-if="orders.length === 0" :text="$t('mkt.noRedeemRecords')" />
    </scroll-view>
  </view>
</template>
