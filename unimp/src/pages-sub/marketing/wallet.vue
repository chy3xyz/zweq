<script setup lang="ts">
import { ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import type { IBalancePlan } from '@/api/marketing'
import { getWalletBalance, listBalancePlans, rechargePlan } from '@/api/marketing'
import { t } from '@/i18n'
import { useFanStore } from '@/store/fan'
import { fenToYuan } from '@/utils/format'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '钱包',
  },
})

const fanStore = useFanStore()
const plans = ref<IBalancePlan[]>([])
const balance = ref(0)

function load() {
  listBalancePlans().then((list) => {
    plans.value = list
  })
  getWalletBalance().then((w) => {
    balance.value = w.balance
  }).catch(() => {
    balance.value = 0
  })
}

function onRecharge(plan: IBalancePlan) {
  rechargePlan(plan.id, fanStore.openid).then(() => {
    uni.showToast({ title: t('mkt.rechargeSuccess'), icon: 'success' })
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
    <fg-navbar :title="$t('mkt.wallet')" />
    <scroll-view scroll-y class="z-body">
      <fg-asset-card :label="$t('mkt.myBalance')" :value="`¥${fenToYuan(balance)}`" />

      <fg-section-title :title="$t('mkt.rechargePlans')" />

      <view v-for="p in plans" :key="p.id" class="mx-4 mb-2 flex flex-row items-center justify-between rounded-3 bg-white p-6">
        <view class="flex flex-1 flex-col">
          <text class="text-[15px] text-[#1e293b] font-bold">{{ p.name }}</text>
          <text v-if="p.bonus > 0" class="mt-2 text-[13px] text-[#ef4444]">{{ $t('mkt.planBonus', { bonus: p.bonus }) }}</text>
        </view>
        <view class="flex flex-row items-center">
          <text class="text-[18px] text-[#ef4444] font-bold">¥{{ fenToYuan(p.amount) }}</text>
          <view class="ml-5 rounded-full bg-primary px-7 py-3" @click="onRecharge(p)">
            <text class="text-[14px] text-white">{{ $t('mkt.recharge') }}</text>
          </view>
        </view>
      </view>
      <fg-empty-view v-if="plans.length === 0" :text="$t('mkt.noRechargePlans')" />
    </scroll-view>
  </view>
</template>
