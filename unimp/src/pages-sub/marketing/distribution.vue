<script setup lang="ts">
import { ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import type { IDistribution } from '@/api/scene'
import { getDistribution, joinDistribution, withdrawDistribution } from '@/api/scene'
import { t } from '@/i18n'
import { useFanStore } from '@/store/fan'
import { fenToYuan } from '@/utils/format'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '分销',
  },
})

const fanStore = useFanStore()
const dist = ref<IDistribution | null>(null)
const withdrawAmount = ref('')

function load() {
  getDistribution().then((d) => {
    dist.value = d
  })
}

function onJoin() {
  joinDistribution('').then(() => {
    uni.showToast({ title: t('mkt.joinSuccess'), icon: 'success' })
    load()
  })
}

function onWithdraw() {
  const amount = Number.parseInt(withdrawAmount.value)
  if (!amount || amount <= 0) {
    uni.showToast({ title: t('mkt.withdrawEmpty'), icon: 'none' })
    return
  }
  withdrawDistribution(amount).then(() => {
    uni.showToast({ title: t('mkt.withdrawSuccess'), icon: 'success' })
    withdrawAmount.value = ''
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
    <fg-navbar :title="$t('mkt.distribution')" />
    <scroll-view scroll-y class="z-body">
      <view v-if="!dist" class="mx-4 mt-4 flex flex-col items-center rounded-3 bg-white px-8 py-12">
        <text class="text-[20px] text-[#1e293b] font-bold">{{ $t('mkt.becomeDistributor') }}</text>
        <text class="mt-3 text-[13px] text-[#94a3b8]">{{ $t('mkt.joinDesc') }}</text>
        <view class="mt-10 w-full flex items-center justify-center rounded-full bg-primary py-6" @click="onJoin">
          <text class="text-[16px] text-white font-bold">{{ $t('mkt.joinNow') }}</text>
        </view>
      </view>

      <view v-else class="flex flex-col p-4">
        <view class="mb-4 flex flex-col rounded-3 bg-white p-8">
          <text class="text-[13px] text-[#64748b]">{{ $t('mkt.withdrawableCommission') }}</text>
          <text class="mt-2 text-[36px] text-[#ef4444] font-bold">¥{{ fenToYuan(dist.commission_balance) }}</text>
        </view>
        <view class="mb-4 flex flex-col rounded-3 bg-white p-8">
          <text class="text-[13px] text-[#64748b]">{{ $t('mkt.totalCommission') }}</text>
          <text class="mt-2 text-[36px] text-[#ef4444] font-bold">¥{{ fenToYuan(dist.total_commission) }}</text>
        </view>

        <view class="flex flex-col rounded-3 bg-white p-8">
          <text class="text-[14px] text-[#1e293b]">{{ $t('mkt.withdrawLabel') }}</text>
          <input
            v-model="withdrawAmount"
            class="mt-4 rounded-2 bg-[#f8fafc] px-6 py-5 text-[15px] text-[#1e293b]"
            type="number"
            :placeholder="$t('mkt.withdrawPlaceholder')"
          >
          <view class="mt-6 flex items-center justify-center rounded-full bg-primary py-6" @click="onWithdraw">
            <text class="text-[16px] text-white font-bold">{{ $t('mkt.withdraw') }}</text>
          </view>
        </view>
      </view>
    </scroll-view>
  </view>
</template>
