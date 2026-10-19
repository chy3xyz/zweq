<script setup lang="ts">
import { computed, ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import type { IDrawConfig, IDrawRecord } from '@/api/marketing'
import { draw, getDrawConfig, listDrawRecords } from '@/api/marketing'
import { t } from '@/i18n'
import { useFanStore } from '@/store/fan'
import { formatTime } from '@/utils/format'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '大转盘',
  },
})

const fanStore = useFanStore()
const config = ref<IDrawConfig | null>(null)
const records = ref<IDrawRecord[]>([])

const drawCost = computed(() => config.value?.cost ?? 0)
const dailyLimit = computed(() => config.value?.daily_limit ?? 0)
const prizeCount = computed(() => config.value?.prize_count ?? 0)
const prizeNames = computed(() => {
  const arr: string[] = []
  for (let i = 1; i <= prizeCount.value; i++) {
    arr.push(t('mkt.prizeN', { n: i }))
  }
  return arr
})

function load() {
  getDrawConfig().then((c) => {
    config.value = c
  })
  listDrawRecords(1, 20).then((res) => {
    records.value = res.list
  })
}

function onDraw() {
  draw().then((r) => {
    uni.showModal({
      title: t('mkt.drawResult'),
      content: `${r.prize_name}（+${r.points} 积分）`,
      showCancel: false,
    })
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
    <fg-navbar :title="$t('mkt.luckyDraw')" />
    <scroll-view scroll-y class="z-body">
      <view class="mx-4 mt-4 flex flex-row items-center justify-around rounded-3 bg-white p-6">
        <text class="text-[13px] text-[#64748b]">{{ $t('mkt.drawCost', { cost: drawCost }) }}</text>
        <text class="text-[13px] text-[#64748b]">{{ $t('mkt.drawDailyTimes', { count: dailyLimit }) }}</text>
        <text class="text-[13px] text-[#64748b]">{{ $t('mkt.drawPrizeCount', { count: prizeCount }) }}</text>
      </view>

      <view class="flex flex-row justify-center py-6">
        <view class="h-[560rpx] w-[560rpx] flex flex-row flex-wrap items-center justify-center rounded-full bg-[#fef3c7]">
          <view v-for="p in prizeNames" :key="p" class="h-1/3 w-1/3 flex flex-row items-center justify-center">
            <text class="text-[13px] text-[#92400e] font-bold">{{ p }}</text>
          </view>
        </view>
      </view>

      <view class="px-4 pb-4">
        <view class="w-full flex items-center justify-center rounded-full bg-primary py-6" @click="onDraw">
          <text class="text-[16px] text-white font-bold">{{ $t('mkt.drawBtn', { cost: drawCost }) }}</text>
        </view>
      </view>

      <view class="px-4 pb-2 pt-4">
        <text class="text-[15px] text-[#1e293b] font-bold">{{ $t('mkt.drawRecord') }}</text>
      </view>

      <view v-for="r in records" :key="r.id" class="mx-4 mb-2 flex flex-row items-center justify-between rounded-3 bg-white p-6">
        <view class="flex flex-col">
          <text class="text-[15px] text-[#1e293b] font-bold">{{ r.prize_name }}</text>
          <text class="mt-1 text-[12px] text-[#94a3b8]">{{ formatTime(r.created_at) }}</text>
        </view>
        <text class="text-[14px] text-[#ef4444]">+{{ r.points }} 积分</text>
      </view>
      <fg-empty-view v-if="records.length === 0" :text="$t('mkt.noDrawRecords')" />
    </scroll-view>
  </view>
</template>
