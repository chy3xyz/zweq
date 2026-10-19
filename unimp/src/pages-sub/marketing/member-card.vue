<script setup lang="ts">
import { computed, ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import type { IMemberCard } from '@/api/marketing'
import { getMemberCard, openMemberCard } from '@/api/marketing'
import { t } from '@/i18n'
import { useFanStore } from '@/store/fan'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '会员卡',
  },
})

const fanStore = useFanStore()
const card = ref<IMemberCard | null>(null)
const discountText = computed(() => {
  const d = card.value?.discount ?? 1000
  return d >= 1000 ? '无折扣' : `${(d / 100).toFixed(1)} 折`
})

function load() {
  getMemberCard().then((c) => {
    card.value = c
  }).catch(() => {})
}

function onOpenCard() {
  openMemberCard().then(() => {
    uni.showToast({ title: t('mkt.openCardSuccess'), icon: 'success' })
    load()
  }).catch(() => {})
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
    <fg-navbar :title="$t('mkt.memberCard')" />
    <scroll-view scroll-y class="z-body">
      <view v-if="card" class="mx-4 mt-4 flex flex-col rounded-4 from-[#f43f5e] to-[#ef4444] bg-gradient-to-br p-8">
        <view class="flex flex-row items-center justify-between">
          <text class="text-[20px] text-white font-bold">{{ card.level_name }}</text>
          <view class="rounded-full bg-white/25 px-5 py-1">
            <text class="text-[13px] text-white">Lv.{{ card.level }}</text>
          </view>
        </view>
        <view class="mt-8 flex flex-row items-center justify-around">
          <view class="flex flex-col items-center">
            <text class="text-[26px] text-white font-bold">{{ card.points }}</text>
            <text class="mt-2 text-[12px] text-white/85">{{ $t('mkt.currentPoints') }}</text>
          </view>
          <view class="flex flex-col items-center">
            <text class="text-[26px] text-white font-bold">{{ card.total_points }}</text>
            <text class="mt-2 text-[12px] text-white/85">{{ $t('mkt.totalPoints') }}</text>
          </view>
          <view class="flex flex-col items-center">
            <text class="text-[26px] text-white font-bold">{{ discountText }}</text>
            <text class="mt-2 text-[12px] text-white/85">{{ $t('mkt.discount') }}</text>
          </view>
        </view>
      </view>

      <view v-else class="mx-4 mt-4 flex flex-col items-center rounded-3 bg-white px-8 py-12">
        <text class="text-[18px] text-[#1e293b] font-bold">{{ $t('mkt.noCard') }}</text>
        <text class="mt-3 text-[13px] text-[#94a3b8]">{{ $t('mkt.noCardDesc') }}</text>
        <view class="mt-10 w-full flex items-center justify-center rounded-full bg-primary py-6" @click="onOpenCard">
          <text class="text-[16px] text-white font-bold">{{ $t('mkt.openCard') }}</text>
        </view>
      </view>
    </scroll-view>
  </view>
</template>
