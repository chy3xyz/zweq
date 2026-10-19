<script setup lang="ts">
import { ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import type { ICheckinRecord } from '@/api/marketing'
import { checkin, listCheckinRecords } from '@/api/marketing'
import { t } from '@/i18n'
import { useFanStore } from '@/store/fan'
import { formatDate } from '@/utils/format'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '签到',
  },
})

const fanStore = useFanStore()
const records = ref<ICheckinRecord[]>([])

function load() {
  listCheckinRecords(1, 20).then((res) => {
    records.value = res.list
  })
}

function onCheckin() {
  checkin().then((r) => {
    const msg = r.fresh ? t('mkt.checkinSuccessWithPoints', { points: r.points }) : t('mkt.alreadyCheckin')
    uni.showToast({ title: msg, icon: r.fresh ? 'success' : 'none' })
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
    <fg-navbar :title="$t('mkt.checkin')" />
    <scroll-view scroll-y class="z-body">
      <view class="mx-4 mt-4 flex flex-col items-center rounded-3 bg-white px-8 py-10">
        <text class="text-[20px] text-[#1e293b] font-bold">{{ $t('mkt.dailyCheckin') }}</text>
        <text class="mt-2 text-[13px] text-[#94a3b8]">{{ $t('mkt.checkinRewardDesc') }}</text>
        <view class="mt-10 w-full flex items-center justify-center rounded-full bg-primary py-6" @click="onCheckin">
          <text class="text-[16px] text-white font-bold">{{ $t('mkt.checkinNow') }}</text>
        </view>
      </view>

      <view class="px-4 pb-2 pt-4">
        <text class="text-[15px] text-[#1e293b] font-bold">{{ $t('mkt.checkinRecords') }}</text>
      </view>

      <view v-for="r in records" :key="r.id" class="mx-4 mb-2 flex flex-row items-center justify-between rounded-3 bg-white px-6 py-5">
        <text class="text-[14px] text-[#1e293b]">{{ formatDate(r.day * 86400) }}</text>
        <text class="text-[14px] text-[#ef4444]">+{{ r.points }} 积分</text>
      </view>

      <fg-empty-view v-if="records.length === 0" :text="$t('mkt.noCheckinRecords')" />
    </scroll-view>
  </view>
</template>
