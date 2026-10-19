<script setup lang="ts">
import { computed, ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import { getMemberCard, getWalletBalance, listMyCoupons } from '@/api/marketing'
import { listOrders } from '@/api/shop'
import { t } from '@/i18n'
import { useAppStore } from '@/store/app'
import { useFanStore } from '@/store/fan'
import { setCurIdxByPath } from '@/tabbar/store'
import { LOGIN_PAGE } from '@/router/config'

definePage({
  style: {
    navigationBarTitleText: '我的',
  },
})

const fanStore = useFanStore()
const appStore = useAppStore()

const langText = computed(() => appStore.locale === 'zh-CN' ? '简体中文' : 'English')

function toggleLang() {
  appStore.toggleLocale()
}

const points = ref(0)
const couponCount = ref(0)
const walletBalance = ref(0)
const memberTag = ref(t('app.regularMember'))
const unpaidCount = ref(0)
const unshippedCount = ref(0)
const receivedCount = ref(0)

const avatarUrl = computed(() => fanStore.avatar || '/static/logo.png')
const nickname = computed(() => fanStore.nickname === '' ? t('app.wechatUser') : fanStore.nickname)

function loadAssets() {
  if (!fanStore.hasLogin) {
    points.value = 0
    couponCount.value = 0
    walletBalance.value = 0
    unpaidCount.value = 0
    unshippedCount.value = 0
    receivedCount.value = 0
    return
  }
  points.value = fanStore.points
  getWalletBalance().then((w) => {
    walletBalance.value = w.balance
  }).catch(() => {
    walletBalance.value = 0
  })
  listMyCoupons(1, 1).then((res) => {
    couponCount.value = res.total
  }).catch(() => {})
  getMemberCard().then((m) => {
    if (m)
      memberTag.value = m.level_name
  }).catch(() => {})
  loadOrderCounts()
}

function loadOrderCounts() {
  listOrders(fanStore.openid, 1, 1, 0).then((res) => {
    unpaidCount.value = res.total
  }).catch(() => {})
  listOrders(fanStore.openid, 1, 1, 1).then((res) => {
    unshippedCount.value = res.total
  }).catch(() => {})
  listOrders(fanStore.openid, 1, 1, 2).then((res) => {
    receivedCount.value = res.total
  }).catch(() => {})
}

function handleLogin() {
  uni.navigateTo({ url: LOGIN_PAGE })
}

function goOrders(status: number) {
  uni.navigateTo({ url: `/pages-sub/shop/order-list?status=${status}` })
}

function goProfile() {
  uni.navigateTo({ url: '/pages-sub/shop/profile' })
}

function goCoupons() {
  uni.navigateTo({ url: '/pages-sub/marketing/coupon-center' })
}

function goWallet() {
  uni.navigateTo({ url: '/pages-sub/marketing/wallet' })
}

function goAddress() {
  uni.navigateTo({ url: '/pages-sub/shop/address-list' })
}

function goFavorites() {
  uni.navigateTo({ url: '/pages-sub/shop/favorite-list' })
}

function goMember() {
  uni.navigateTo({ url: '/pages-sub/marketing/member-card' })
}

function goDistribution() {
  uni.navigateTo({ url: '/pages-sub/marketing/distribution' })
}

function goInvite() {
  uni.navigateTo({ url: '/pages-sub/marketing/invite' })
}

function goMarketing(url: string) {
  uni.navigateTo({ url })
}

function handleLogout() {
  uni.showModal({
    title: '提示',
    content: '确定要退出登录吗？',
    success: (res) => {
      if (res.confirm) {
        fanStore.clear()
        uni.showToast({ title: '退出登录成功', icon: 'success' })
        setTimeout(() => {
          const targetUrl = '/pages/index/index'
          setCurIdxByPath(targetUrl)
          uni.switchTab({ url: targetUrl })
        }, 0)
      }
    },
  })
}

onShow(() => {
  loadAssets()
})
</script>

<template>
  <view class="page">
    <fg-user-header
      :avatar="avatarUrl"
      :nickname="nickname"
      :member-tag="memberTag"
      :points="points"
      :coupon-count="couponCount"
      :wallet-balance="walletBalance"
      :logged-in="fanStore.hasLogin"
      @profile="goProfile"
      @wallet="goWallet"
      @coupons="goCoupons"
      @login="handleLogin"
    />

    <view class="card">
      <view class="card-head">
        <text class="card-title">{{ $t('app.myOrders') }}</text>
        <text class="card-more" @click="goOrders(-1)">{{ $t('app.allOrders') }} ›</text>
      </view>
      <view class="order-status">
        <view class="status-item" @click="goOrders(0)">
          <view class="status-icon">
            <text class="status-emoji">💳</text>
            <text v-if="unpaidCount > 0" class="status-badge">{{ unpaidCount }}</text>
          </view>
          <text class="status-name">{{ $t('app.pendingPay') }}</text>
        </view>
        <view class="status-item" @click="goOrders(1)">
          <view class="status-icon">
            <text class="status-emoji">📦</text>
            <text v-if="unshippedCount > 0" class="status-badge">{{ unshippedCount }}</text>
          </view>
          <text class="status-name">{{ $t('app.pendingShip') }}</text>
        </view>
        <view class="status-item" @click="goOrders(2)">
          <view class="status-icon">
            <text class="status-emoji">🚚</text>
            <text v-if="receivedCount > 0" class="status-badge">{{ receivedCount }}</text>
          </view>
          <text class="status-name">{{ $t('app.pendingReceive') }}</text>
        </view>
        <view class="status-item" @click="goOrders(-1)">
          <view class="status-icon">
            <text class="status-emoji">📋</text>
          </view>
          <text class="status-name">{{ $t('app.allOrders') }}</text>
        </view>
      </view>
    </view>

    <view class="card">
      <view class="card-head">
        <text class="card-title">{{ $t('app.commonFunc') }}</text>
      </view>
      <view class="func-grid">
        <view class="func-item" @click="goAddress">
          <text class="func-emoji">📍</text>
          <text class="func-name">{{ $t('app.address') }}</text>
        </view>
        <view class="func-item" @click="goFavorites">
          <text class="func-emoji">⭐</text>
          <text class="func-name">{{ $t('app.myFavorites') }}</text>
        </view>
        <view class="func-item" @click="goMember">
          <text class="func-emoji">💳</text>
          <text class="func-name">{{ $t('app.memberCenter') }}</text>
        </view>
        <view class="func-item" @click="goDistribution">
          <text class="func-emoji">💰</text>
          <text class="func-name">{{ $t('app.distribution') }}</text>
        </view>
        <view class="func-item" @click="goInvite">
          <text class="func-emoji">🎁</text>
          <text class="func-name">{{ $t('app.invite') }}</text>
        </view>
      </view>
    </view>

    <view class="card">
      <view class="card-head">
        <text class="card-title">{{ $t('app.marketingCenter') }}</text>
      </view>
      <view class="func-grid">
        <view class="func-item" @click="goMarketing('/pages-sub/marketing/checkin')">
          <text class="func-emoji">📅</text><text class="func-name">签到</text>
        </view>
        <view class="func-item" @click="goMarketing('/pages-sub/marketing/lucky-draw')">
          <text class="func-emoji">🎰</text><text class="func-name">大转盘</text>
        </view>
        <view class="func-item" @click="goMarketing('/pages-sub/marketing/coupon-center')">
          <text class="func-emoji">🎫</text><text class="func-name">{{ $t('app.couponCenter') }}</text>
        </view>
        <view class="func-item" @click="goMarketing('/pages-sub/marketing/points-mall')">
          <text class="func-emoji">🛒</text><text class="func-name">{{ $t('app.pointsMall') }}</text>
        </view>
        <view class="func-item" @click="goMarketing('/pages-sub/marketing/vote')">
          <text class="func-emoji">🗳️</text><text class="func-name">投票</text>
        </view>
        <view class="func-item" @click="goMarketing('/pages-sub/marketing/seckill')">
          <text class="func-emoji">⚡</text><text class="func-name">秒杀</text>
        </view>
        <view class="func-item" @click="goMarketing('/pages-sub/marketing/wallet')">
          <text class="func-emoji">👛</text><text class="func-name">{{ $t('app.wallet') }}</text>
        </view>
      </view>
    </view>

    <view class="logout-wrap">
      <view class="logout-btn" @click="toggleLang">
        <text class="logout-text">语言：{{ langText }}</text>
      </view>
    </view>

    <view class="logout-wrap">
      <view v-if="fanStore.hasLogin" class="logout-btn" @click="handleLogout">
        <text class="logout-text">{{ $t('app.logout') }}</text>
      </view>
      <view v-else class="logout-btn" @click="handleLogin">
        <text class="logout-text">{{ $t('app.login') }}</text>
      </view>
    </view>
  </view>
</template>

<style scoped lang="scss">
.page {
  min-height: 100vh;
  padding-bottom: 200rpx;
  background-color: #f8f8f8;
  display: flex;
  flex-direction: column;
}
.card {
  margin: 28rpx 28rpx 0 28rpx;
  padding: 28rpx;
  background-color: #ffffff;
  border-radius: 24rpx;
  display: flex;
  flex-direction: column;
  box-shadow: var(--z-shadow);
}
.card-head {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 20rpx;
}
.card-title {
  font-size: 16px;
  color: #1e293b;
  font-weight: 700;
}
.card-more {
  font-size: 12px;
  color: #94a3b8;
}
.order-status {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-around;
}
.status-item {
  display: flex;
  flex-direction: column;
  align-items: center;
}
.status-icon {
  position: relative;
  width: 76rpx;
  height: 76rpx;
  border-radius: 38rpx;
  background-color: #f5f7fb;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.status-emoji {
  font-size: 38rpx;
}
.status-badge {
  position: absolute;
  top: -8rpx;
  right: -20rpx;
  min-width: 30rpx;
  height: 30rpx;
  padding: 0 8rpx;
  border-radius: 15rpx;
  background-color: #ef4444;
  color: #ffffff;
  font-size: 20rpx;
  line-height: 30rpx;
  text-align: center;
}
.status-name {
  margin-top: 8rpx;
  font-size: 22rpx;
  color: #475569;
}
.func-grid {
  display: flex;
  flex-direction: row;
  flex-wrap: wrap;
}
.func-item {
  width: 20%;
  display: flex;
  flex-direction: column;
  align-items: center;
  margin-bottom: 16rpx;
}
.func-emoji {
  font-size: 38rpx;
  width: 72rpx;
  height: 72rpx;
  border-radius: 36rpx;
  background-color: #f5f7fb;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.func-name {
  margin-top: 8rpx;
  font-size: 22rpx;
  color: #475569;
}
.logout-wrap {
  margin-top: 24rpx;
  padding: 0 24rpx;
}
.logout-btn {
  height: 92rpx;
  border-radius: 46rpx;
  background-color: #ffffff;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  box-shadow: var(--z-shadow);
}
.logout-text {
  font-size: 15px;
  color: var(--z-text-2, #475569);
}
</style>
