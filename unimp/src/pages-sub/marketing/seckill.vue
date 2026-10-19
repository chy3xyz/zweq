<script setup lang="ts">
import { ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import type { ISeckill, ISeckillOrder } from '@/api/scene'
import { listSeckill, listSeckillOrders, seckillRush } from '@/api/scene'
import { t } from '@/i18n'
import { useFanStore } from '@/store/fan'
import { fenToYuan, formatTime } from '@/utils/format'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '秒杀',
  },
})

const fanStore = useFanStore()
const activities = ref<ISeckill[]>([])
const orders = ref<ISeckillOrder[]>([])

function load() {
  listSeckill(1, 20).then((res) => {
    activities.value = res.list
  })
  listSeckillOrders(1, 20).then((res) => {
    orders.value = res.list
  })
}

function onRush(activity: ISeckill) {
  seckillRush(activity.id, 1).then(() => {
    uni.showToast({ title: t('mkt.rushSuccess'), icon: 'success' })
    load()
  })
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
    <fg-navbar :title="$t('mkt.seckill')" />
    <scroll-view scroll-y class="z-body">
      <fg-section-title :title="$t('mkt.seckillActivity')" />

      <view v-for="s in activities" :key="s.id" class="mx-4 mb-2 flex flex-row items-center justify-between rounded-3 bg-white p-6">
        <view class="flex flex-1 flex-col">
          <text class="text-[15px] text-[#1e293b] font-bold">{{ s.title }}</text>
          <view class="mt-2 flex flex-row items-center">
            <text class="text-[18px] text-[#ef4444] font-bold">{{ fenToYuan(s.price) }}</text>
            <text class="ml-3 text-[13px] text-[#94a3b8] line-through">¥{{ fenToYuan(s.original_price) }}</text>
          </view>
          <text class="mt-1 text-[12px] text-[#94a3b8]">{{ $t('mkt.seckillStock', { stock: s.stock, sold: s.sold }) }}</text>
        </view>
        <view class="rounded-full bg-primary px-7 py-3" @click="onRush(s)">
          <text class="text-[14px] text-white">{{ $t('mkt.rush') }}</text>
        </view>
      </view>
      <fg-empty-view v-if="activities.length === 0" :text="$t('mkt.noSeckillActivities')" />

      <fg-section-title :title="$t('mkt.mySeckillOrders')" />

      <view v-for="o in orders" :key="o.id" class="mx-4 mb-2 flex flex-row items-center justify-between rounded-3 bg-white p-6">
        <view class="flex flex-1 flex-col">
          <text class="text-[14px] text-[#1e293b]">{{ $t('mkt.activityId', { id: o.activity_id }) }}</text>
          <text class="mt-1 text-[13px] text-[#64748b]">{{ $t('mkt.quantityLabel', { count: o.quantity }) }}</text>
        </view>
        <text class="text-[13px] text-[#94a3b8]">{{ formatTime(o.created_at) }}</text>
      </view>
      <fg-empty-view v-if="orders.length === 0" :text="$t('mkt.noSeckillOrders')" />
    </scroll-view>
  </view>
</template>
