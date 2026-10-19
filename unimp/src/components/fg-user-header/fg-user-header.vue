<script setup lang="ts">
import { t } from '@/i18n'
import { fenToYuan } from '@/utils/format'

withDefaults(defineProps<{
  avatar?: string
  nickname?: string
  memberTag?: string
  points?: number
  couponCount?: number
  walletBalance?: number
  loggedIn?: boolean
}>(), {
  avatar: '',
  nickname: () => t('app.wechatUser'),
  memberTag: () => t('app.regularMember'),
  points: 0,
  couponCount: 0,
  walletBalance: 0,
  loggedIn: false,
})

const emit = defineEmits<{
  (e: 'profile'): void
  (e: 'wallet'): void
  (e: 'coupons'): void
  (e: 'login'): void
}>()
</script>

<template>
  <view class="user-card">
    <view class="user-top">
      <image class="avatar" :src="avatar" @click="emit('profile')" />
      <view class="user-info">
        <text class="nickname">{{ nickname }}</text>
        <text class="member-tag">{{ memberTag }}</text>
      </view>
      <text v-if="!loggedIn" class="login-link" @click="emit('login')">{{ $t('app.goLogin') }} ›</text>
    </view>

    <view class="assets">
      <view class="asset-item" @click="emit('wallet')">
        <text class="asset-num">{{ points }}</text>
        <text class="asset-label">{{ $t('app.points') }}</text>
      </view>
      <view class="asset-item" @click="emit('coupons')">
        <text class="asset-num">{{ couponCount }}</text>
        <text class="asset-label">{{ $t('app.myCoupons') }}</text>
      </view>
      <view class="asset-item" @click="emit('wallet')">
        <text class="asset-num">¥{{ fenToYuan(walletBalance) }}</text>
        <text class="asset-label">{{ $t('app.wallet') }}</text>
      </view>
    </view>
  </view>
</template>

<style scoped lang="scss">
.user-card {
  padding: 48rpx 32rpx 32rpx 32rpx;
  background-image: linear-gradient(160deg, var(--theme-color, #0957de), #4f7cff);
  border-bottom-left-radius: 40rpx;
  border-bottom-right-radius: 40rpx;
  display: flex;
  flex-direction: column;
  box-shadow: 0 16rpx 40rpx rgba(9, 87, 222, 0.18);
}
.user-top {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: flex-start;
}
.avatar {
  width: 124rpx;
  height: 124rpx;
  border-radius: 62rpx;
  border-width: 4rpx;
  border-style: solid;
  border-color: rgba(255, 255, 255, 0.75);
  box-shadow: 0 8rpx 24rpx rgba(15, 23, 42, 0.18);
}
.user-info {
  flex: 1;
  margin-left: 20rpx;
  display: flex;
  flex-direction: column;
}
.nickname {
  font-size: 36rpx;
  color: #ffffff;
  font-weight: 700;
}
.member-tag {
  margin-top: 10rpx;
  padding: 4rpx 16rpx;
  border-radius: 20rpx;
  align-self: flex-start;
  background-color: rgba(255, 255, 255, 0.22);
  font-size: 22rpx;
  color: #ffffff;
}
.login-link {
  font-size: 28rpx;
  color: #ffffff;
  font-weight: 700;
}
.assets {
  margin-top: 32rpx;
  padding: 26rpx 0;
  border-radius: 20rpx;
  background-color: rgba(255, 255, 255, 0.16);
  display: flex;
  flex-direction: row;
  align-items: center;
}
.asset-item {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
}
.asset-num {
  font-size: 40rpx;
  color: #ffffff;
  font-weight: 700;
}
.asset-label {
  margin-top: 8rpx;
  font-size: 22rpx;
  color: rgba(255, 255, 255, 0.85);
}
</style>
