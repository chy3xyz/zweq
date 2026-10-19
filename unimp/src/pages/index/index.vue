<script setup lang="ts">
import { computed, ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import type { IProduct } from '@/api/shop'
import { listProducts } from '@/api/shop'
import { t } from '@/i18n'
import { fenToYuan } from '@/utils/format'
import { systemInfo } from '@/utils/systemInfo'

definePage({
  type: 'home',
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '首页',
  },
})

interface IBanner {
  title: string
  subtitle: string
  bg: string
}

interface INav {
  key: string
  emoji: string
  name: string
  url: string
  bg: string
}

interface IScene {
  key: string
  emoji: string
  name: string
  url: string
}

const statusBarHeight = computed(() => systemInfo.value?.statusBarHeight ?? 0)

const banners: IBanner[] = [
  { title: '新人专享', subtitle: '首单立减 · 精选好物', bg: '#0957DE' },
  { title: '限时秒杀', subtitle: '低价抢购 · 手慢无', bg: '#ef4444' },
  { title: '积分狂欢', subtitle: '签到抽奖 · 攒积分换好礼', bg: '#f97316' },
]

const navs: INav[] = [
  { key: 'category', emoji: '🗂️', name: t('app.allCategory'), url: 'switchTab:/pages/category/category', bg: '#fef2f2' },
  { key: 'coupon', emoji: '🎫', name: t('app.couponCenter'), url: '/pages-sub/marketing/coupon-center', bg: '#fef3c7' },
  { key: 'checkin', emoji: '📅', name: t('app.dailyCheckin'), url: '/pages-sub/marketing/checkin', bg: '#dcfce7' },
  { key: 'points', emoji: '🛒', name: t('app.pointsMall'), url: '/pages-sub/marketing/points-mall', bg: '#dbeafe' },
  { key: 'member', emoji: '💳', name: t('app.memberCenter'), url: '/pages-sub/marketing/member-card', bg: '#ede9fe' },
]

const scenes: IScene[] = [
  { key: 'checkin', emoji: '📅', name: '签到', url: '/pages-sub/marketing/checkin' },
  { key: 'luckyDraw', emoji: '🎰', name: '大转盘', url: '/pages-sub/marketing/lucky-draw' },
  { key: 'coupon', emoji: '🎫', name: '优惠券', url: '/pages-sub/marketing/coupon-center' },
  { key: 'vote', emoji: '🗳️', name: '投票', url: '/pages-sub/marketing/vote' },
  { key: 'seckill', emoji: '⚡', name: '秒杀', url: '/pages-sub/marketing/seckill' },
  { key: 'memberCard', emoji: '💳', name: '会员卡', url: '/pages-sub/marketing/member-card' },
  { key: 'distribution', emoji: '💰', name: '分销', url: '/pages-sub/marketing/distribution' },
  { key: 'points', emoji: '🛒', name: '积分商城', url: '/pages-sub/marketing/points-mall' },
]

const products = ref<IProduct[]>([])

function loadProducts() {
  listProducts(0, 1, 10).then((res) => {
    products.value = res.list
  }).catch(() => {
    products.value = []
  })
}

function goSearch() {
  uni.navigateTo({ url: '/pages/search/search' })
}

function onBanner(banner: IBanner) {
  uni.showToast({ title: banner.title, icon: 'none' })
}

function onNav(nav: INav) {
  if (nav.url.startsWith('switchTab:')) {
    uni.switchTab({ url: nav.url.substring(10) })
    return
  }
  if (nav.url !== '') {
    uni.navigateTo({ url: nav.url })
  }
}

function onScene(scene: IScene) {
  if (scene.url !== '') {
    uni.navigateTo({ url: scene.url })
  }
}

function goProduct(product: IProduct) {
  uni.navigateTo({ url: `/pages-sub/shop/product-detail?id=${product.id}` })
}

onShow(() => {
  loadProducts()
})
</script>

<template>
  <view class="page">
    <view class="header">
      <view class="header-status" :style="{ height: `${statusBarHeight}px` }" />
      <view class="header-brand">
        <text class="header-logo">ZWEQ</text>
      </view>
      <view class="search-bar" @click="goSearch">
        <text class="search-icon">🔍</text>
        <text class="search-placeholder">{{ $t('app.searchPlaceholder') }}</text>
      </view>
    </view>

    <swiper
      class="banner"
      circular
      autoplay
      :interval="4000"
      indicator-dots
      indicator-color="rgba(255,255,255,0.5)"
      indicator-active-color="#ffffff"
    >
      <swiper-item v-for="(b, i) in banners" :key="i">
        <view class="banner-item" :style="{ backgroundColor: b.bg }" @click="onBanner(b)">
          <text class="banner-title">{{ b.title }}</text>
          <text class="banner-sub">{{ b.subtitle }}</text>
        </view>
      </swiper-item>
    </swiper>

    <view class="kingkong">
      <view v-for="n in navs" :key="n.key" class="kingkong-item" @click="onNav(n)">
        <view class="kingkong-icon" :style="{ backgroundColor: n.bg }">
          <text class="kingkong-emoji">{{ n.emoji }}</text>
        </view>
        <text class="kingkong-name">{{ n.name }}</text>
      </view>
    </view>

    <view class="scene-section">
      <view class="section-head">
        <text class="section-title">{{ $t('app.wechatScenes') }}</text>
        <text class="section-sub">{{ $t('app.subtitle_scenes') }}</text>
      </view>
      <view class="scene-grid">
        <view v-for="s in scenes" :key="s.key" class="scene-item" @click="onScene(s)">
          <text class="scene-emoji">{{ s.emoji }}</text>
          <text class="scene-name">{{ s.name }}</text>
        </view>
      </view>
    </view>

    <view class="section">
      <view class="section-head">
        <text class="section-title">{{ $t('app.guessFavorites') }}</text>
        <text class="section-sub">{{ $t('app.subtitle_guess') }}</text>
      </view>
      <view class="goods-grid">
        <view v-for="p in products" :key="p.id" class="goods-card" @click="goProduct(p)">
          <image class="goods-img" :src="p.image" mode="aspectFill" />
          <view class="goods-info">
            <text class="goods-name">{{ p.name }}</text>
            <text class="goods-price">¥{{ fenToYuan(p.price) }}</text>
          </view>
        </view>
      </view>
      <view v-if="products.length === 0" class="empty">
        <text class="empty-text">{{ $t('app.noResult') }}</text>
      </view>
    </view>

    <view class="tabbar-holder" />
  </view>
</template>

<style scoped lang="scss">
.page {
  padding-bottom: 200rpx;
}
.header {
  padding-bottom: 88rpx;
  background-image: linear-gradient(160deg, var(--theme-color, #0957de), #4f7cff);
  border-bottom-left-radius: 40rpx;
  border-bottom-right-radius: 40rpx;
}
.header-status {
  background-color: transparent;
}
.header-brand {
  display: flex;
  flex-direction: row;
  justify-content: center;
}
.header-logo {
  font-size: 20px;
  color: #ffffff;
  font-weight: 700;
  margin: 8rpx 0;
}
.search-bar {
  margin: 16rpx 28rpx 0 28rpx;
  height: 76rpx;
  padding: 0 28rpx;
  border-radius: 38rpx;
  background-color: #ffffff;
  box-shadow: 0 10rpx 26rpx rgba(15, 23, 42, 0.12);
  display: flex;
  flex-direction: row;
  align-items: center;
}
.search-icon {
  font-size: 26rpx;
  margin-right: 12rpx;
}
.search-placeholder {
  font-size: 14px;
  color: #94a3b8;
}
.banner {
  height: 300rpx;
  margin: -52rpx 28rpx 16rpx 28rpx;
  border-radius: 28rpx;
  overflow: hidden;
  box-shadow: 0 16rpx 40rpx rgba(15, 23, 42, 0.12);
}
.banner-item {
  height: 300rpx;
  border-radius: 28rpx;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
}
.banner-title {
  font-size: 48rpx;
  color: #ffffff;
  font-weight: 700;
}
.banner-sub {
  margin-top: 12rpx;
  font-size: 24rpx;
  color: rgba(255, 255, 255, 0.85);
}
.kingkong {
  margin: 8rpx 28rpx 0 28rpx;
  padding: 26rpx 8rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
  background-color: #ffffff;
  border-radius: 24rpx;
}
.kingkong-item {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
}
.kingkong-icon {
  width: 88rpx;
  height: 88rpx;
  border-radius: 44rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.kingkong-emoji {
  font-size: 40rpx;
}
.kingkong-name {
  margin-top: 8rpx;
  font-size: 24rpx;
  color: #475569;
}
.section {
  margin-top: 28rpx;
  padding: 0 28rpx 24rpx 28rpx;
}
.section-head {
  margin-bottom: 16rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
}
.section-title {
  font-size: 17px;
  color: #1e293b;
  font-weight: 700;
}
.section-sub {
  margin-left: 12rpx;
  font-size: 12px;
  color: #94a3b8;
}
.scene-section {
  margin: 24rpx 28rpx 0 28rpx;
  padding: 26rpx 24rpx 8rpx 24rpx;
  background-color: #ffffff;
  border-radius: 24rpx;
}
.scene-grid {
  display: flex;
  flex-direction: row;
  flex-wrap: wrap;
  justify-content: space-between;
}
.scene-item {
  width: 25%;
  display: flex;
  flex-direction: column;
  align-items: center;
  margin-bottom: 24rpx;
}
.scene-emoji {
  font-size: 44rpx;
}
.scene-name {
  margin-top: 8rpx;
  font-size: 22rpx;
  color: #475569;
}
.goods-grid {
  display: flex;
  flex-direction: row;
  flex-wrap: wrap;
  justify-content: space-between;
}
.goods-card {
  width: 338rpx;
  margin-bottom: 20rpx;
  border-radius: 20rpx;
  overflow: hidden;
  background-color: #ffffff;
  display: flex;
  flex-direction: column;
  box-shadow: var(--z-shadow);
}
.goods-img {
  width: 338rpx;
  height: 280rpx;
}
.goods-info {
  padding: 16rpx;
  display: flex;
  flex-direction: column;
}
.goods-name {
  font-size: 14px;
  color: #1e293b;
}
.goods-price {
  margin-top: 8rpx;
  font-size: 16px;
  color: #ef4444;
  font-weight: 700;
}
.empty {
  padding: 60rpx;
  display: flex;
  flex-direction: column;
  align-items: center;
}
.empty-text {
  font-size: 13px;
  color: #94a3b8;
}
</style>
