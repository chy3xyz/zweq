<script setup lang="ts">
import { computed, ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import type { ICoupon, ICouponUser } from '@/api/marketing'
import { claimCoupon, listCoupons, listMyCoupons } from '@/api/marketing'
import { t } from '@/i18n'
import { useFanStore } from '@/store/fan'
import { fenToYuan, formatTime } from '@/utils/format'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '领券中心',
  },
})

const fanStore = useFanStore()
const coupons = ref<ICoupon[]>([])
const myCoupons = ref<ICouponUser[]>([])
const claimableCoupons = computed(() => {
  const now = Math.floor(Date.now() / 1000)
  return coupons.value.filter(c => c.end_at === 0 || c.end_at > now)
})

function load() {
  listCoupons(1, 20).then((res) => {
    coupons.value = res.list
  }).catch(() => {})
  listMyCoupons(1, 20).then((res) => {
    myCoupons.value = res.list
  }).catch(() => {})
}

function onClaim(coupon: ICoupon) {
  claimCoupon(coupon.id).then(() => {
    uni.showToast({ title: t('mkt.claimSuccess'), icon: 'success' })
    load()
  }).catch(() => {})
}

function couponStatusText(status: string): string {
  if (status === 'unused')
    return t('mkt.couponUnused')
  if (status === 'used')
    return t('mkt.couponUsed')
  if (status === 'expired')
    return t('mkt.couponExpired')
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
    <fg-navbar :title="$t('mkt.couponCenter')" />
    <scroll-view scroll-y class="z-body">
      <view class="px-4 pb-2 pt-4">
        <text class="text-[15px] text-[#1e293b] font-bold">{{ $t('mkt.claimableCoupons') }}</text>
      </view>

      <view v-for="c in claimableCoupons" :key="c.id" class="mx-4 mb-2 flex flex-row items-center rounded-3 bg-white p-6">
        <view class="w-[180rpx] flex flex-col">
          <text class="text-[28px] text-[#ef4444] font-bold">¥{{ fenToYuan(c.amount) }}</text>
          <text class="mt-1 text-[12px] text-[#94a3b8]">{{ $t('mkt.thresholdAvailable', { amount: fenToYuan(c.min_amount) }) }}</text>
        </view>
        <view class="ml-4 flex flex-1 flex-col">
          <text class="text-[15px] text-[#1e293b] font-bold">{{ c.title }}</text>
          <text class="mt-2 text-[12px] text-[#94a3b8]">{{ formatTime(c.start_at) }} ~ {{ formatTime(c.end_at) }}</text>
        </view>
        <view class="rounded-full bg-primary px-7 py-3" @click="onClaim(c)">
          <text class="text-[14px] text-white">{{ $t('mkt.claim') }}</text>
        </view>
      </view>
      <fg-empty-view v-if="claimableCoupons.length === 0" :text="$t('mkt.noClaimableCoupons')" />

      <view class="px-4 pb-2 pt-4">
        <text class="text-[15px] text-[#1e293b] font-bold">{{ $t('mkt.myCoupons') }}</text>
      </view>

      <view v-for="m in myCoupons" :key="m.id" class="mx-4 mb-2 flex flex-row items-center justify-between rounded-3 bg-white p-6">
        <view class="flex flex-1 flex-col">
          <text class="text-[14px] text-[#1e293b] font-bold">{{ m.title }} · ¥{{ fenToYuan(m.amount) }}</text>
          <text class="mt-1 text-[12px] text-[#475569]">{{ m.code }}</text>
          <text class="mt-1 text-[12px] text-[#94a3b8]">{{ $t('mkt.claimTime') }} {{ formatTime(m.created_at) }}</text>
        </view>
        <text class="text-[13px] text-[#ef4444]">{{ couponStatusText(m.status) }}</text>
      </view>
      <fg-empty-view v-if="myCoupons.length === 0" :text="$t('mkt.noClaimedCoupons')" />
    </scroll-view>
  </view>
</template>
