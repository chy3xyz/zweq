<script setup lang="ts">
import { ref } from 'vue'
import { onLoad, onShareAppMessage, onShow } from '@dcloudio/uni-app'
import type { IInviteGift, IInviteMy } from '@/api/shop'
import { inviteBind, inviteMy, listInviteGifts } from '@/api/shop'
import { t } from '@/i18n'
import { useFanStore } from '@/store/fan'
import { fenToYuan } from '@/utils/format'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '邀请有礼',
  },
})

const fanStore = useFanStore()
const gifts = ref<IInviteGift[]>([])
const myInvite = ref<IInviteMy>({ invited: 0, invite_code: '' })

onLoad((options) => {
  const query = options as Record<string, string> | undefined
  if (query?.inviter)
    uni.setStorageSync('inviter_openid', query.inviter)
})

onShow(() => {
  if (!fanStore.hasLogin) {
    uni.navigateTo({ url: '/pages-sub/auth/login' })
    return
  }
  bindIfInvited()
  load()
})

/** 若有邀请码且未绑定，绑定邀请关系 */
function bindIfInvited() {
  if (!fanStore.hasLogin)
    return
  const inviter = uni.getStorageSync('inviter_openid')
  if (!inviter || typeof inviter !== 'string')
    return
  if (inviter === fanStore.openid) {
    uni.removeStorageSync('inviter_openid')
    return
  }
  inviteBind(inviter, fanStore.openid).then(() => {
    uni.removeStorageSync('inviter_openid')
    uni.showToast({ title: t('mkt.inviteBindSuccess'), icon: 'success' })
    load()
  }).catch(() => {
    // 已绑定或绑定失败，移除标记避免重复提示
    uni.removeStorageSync('inviter_openid')
  })
}

function load() {
  if (fanStore.openid === '')
    return
  inviteMy(fanStore.openid).then((m) => {
    myInvite.value = m
  }).catch(() => {})
  listInviteGifts().then((list) => {
    gifts.value = list
  }).catch(() => {})
}

onShareAppMessage(() => {
  const inviterParam = myInvite.value.invite_code !== '' ? `?inviter=${myInvite.value.invite_code}` : ''
  return {
    title: t('mkt.inviteShareTitle'),
    path: `/pages-sub/marketing/invite${inviterParam}`,
  }
})

function rewardText(gift: IInviteGift): string {
  if (gift.reward_type === 'points')
    return `${gift.reward_value} 积分`
  return `¥${fenToYuan(gift.reward_value)}`
}

function copyCode() {
  uni.setClipboardData({
    data: myInvite.value.invite_code,
    success: () => {
      uni.showToast({ title: t('mkt.inviteCodeCopied'), icon: 'success' })
    },
  })
}

function onInvite() {
  uni.showModal({
    title: t('mkt.inviteFriends'),
    content: t('mkt.inviteModalContent'),
    success: (res) => {
      if (res.confirm)
        copyCode()
    },
  })
}
</script>

<template>
  <view class="z-page">
    <fg-navbar :title="$t('mkt.invite')" />
    <scroll-view scroll-y class="z-body">
      <view class="flex flex-col items-center from-primary to-[#1890ff] bg-gradient-to-br px-6 py-12">
        <text class="text-[40rpx] text-white font-bold">{{ $t('mkt.inviteTitle') }}</text>
        <text class="mt-4 text-[26rpx] text-white/90">{{ $t('mkt.invitedCount', { count: myInvite.invited }) }}</text>
      </view>

      <view class="mx-4 mt-4 flex flex-col rounded-3 bg-white p-6">
        <text class="text-[15px] text-[#1e293b] font-bold">{{ $t('mkt.myInviteCode') }}</text>
        <view class="mt-4 flex flex-row items-center justify-between">
          <text class="flex-1 text-[16px] text-[#1e293b] font-bold tracking-[2rpx]">{{ myInvite.invite_code }}</text>
          <view class="rounded-full bg-primary px-7 py-3" @click="copyCode">
            <text class="text-[13px] text-white font-bold">{{ $t('mkt.copy') }}</text>
          </view>
        </view>
        <text class="mt-3 text-[12px] text-[#94a3b8]">{{ $t('mkt.inviteTip') }}</text>
      </view>

      <view class="mx-4 mt-4 flex flex-col rounded-3 bg-white p-6">
        <text class="text-[15px] text-[#1e293b] font-bold">{{ $t('mkt.inviteRewards') }}</text>
        <view v-for="g in gifts" :key="g.id" class="mt-4 flex flex-row items-center justify-between rounded-2 bg-[#f8fafc] p-4">
          <text class="text-[14px] text-[#1e293b]">{{ $t('mkt.inviteCount', { count: g.target_count }) }}</text>
          <text class="text-[14px] text-[#ef4444] font-bold">{{ rewardText(g) }}</text>
        </view>
        <text v-if="gifts.length === 0" class="mt-3 text-[12px] text-[#94a3b8]">{{ $t('mkt.moreRewardsComing') }}</text>
      </view>

      <view class="mx-4 my-6 h-[88rpx] flex items-center justify-center rounded-full bg-primary" @click="onInvite">
        <text class="text-[16px] text-white font-bold">{{ $t('mkt.inviteFriends') }}</text>
      </view>
    </scroll-view>
  </view>
</template>
