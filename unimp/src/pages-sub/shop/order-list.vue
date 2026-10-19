<script setup lang="ts">
import { ref } from 'vue'
import { onLoad, onReachBottom, onShow } from '@dcloudio/uni-app'
import type { IOrderSummary } from '@/api/shop'
import { listOrders, orderSummaries } from '@/api/shop'
import { t } from '@/i18n'
import { useFanStore } from '@/store/fan'
import { fenToYuan, formatTime } from '@/utils/format'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '我的订单',
  },
})

interface ITab {
  name: string
  status: number
}

interface IOrderView {
  id: number
  order_no: string
  status: number
  pay_amount: number
  created_at: number
  cover_image: string
  item_count: number
  summary: string
}

const fanStore = useFanStore()
const tabs: ITab[] = [
  { name: t('app.allOrders'), status: -1 },
  { name: t('app.pendingPay'), status: 0 },
  { name: t('app.pendingShip'), status: 1 },
  { name: t('app.pendingReceive'), status: 2 },
  { name: t('app.completed'), status: 3 },
]
const tabIndex = ref(0)
const dataList = ref<IOrderView[]>([])
const page = ref(1)
const pageSize = 20
const hasMore = ref(true)
const loading = ref(false)

onLoad((options) => {
  const query = options as Record<string, string> | undefined
  if (query?.status) {
    const status = Number.parseInt(query.status)
    const idx = tabs.findIndex(tab => tab.status === status)
    if (idx >= 0)
      tabIndex.value = idx
  }
})

onShow(() => {
  reload()
})

onReachBottom(() => {
  if (hasMore.value && !loading.value)
    loadPage()
})

function onTabChange(idx: number) {
  if (tabIndex.value === idx)
    return
  tabIndex.value = idx
  reload()
}

function statusText(status: number): string {
  if (status === 0)
    return t('app.pendingPay')
  if (status === 1)
    return t('app.pendingShip')
  if (status === 2)
    return t('app.pendingReceive')
  if (status === 3)
    return t('app.completed')
  if (status === 4)
    return '已取消'
  return '其它'
}

function reload() {
  page.value = 1
  hasMore.value = true
  dataList.value = []
  loadPage()
}

async function loadPage() {
  if (loading.value)
    return
  loading.value = true
  const status = tabs[tabIndex.value].status
  try {
    const res = await listOrders(fanStore.openid, page.value, pageSize, status)
    const ids = res.list.map(o => o.id)
    const summaries: IOrderSummary[] = ids.length > 0 ? await orderSummaries(ids) : []
    const views = res.list.map((o) => {
      const summary = summaries.find(s => s.order_id === o.id)
      return {
        id: o.id,
        order_no: o.order_no,
        status: o.status,
        pay_amount: o.pay_amount,
        created_at: o.created_at,
        cover_image: summary?.cover_image ?? '',
        item_count: summary?.item_count ?? 0,
        summary: summary?.summary ?? '',
      }
    })
    dataList.value = page.value === 1 ? views : [...dataList.value, ...views]
    hasMore.value = dataList.value.length < res.total
    page.value += 1
  }
  catch (err) {
    console.error('listOrders error:', err)
  }
  finally {
    loading.value = false
  }
}

function goDetail(order: IOrderView) {
  uni.navigateTo({ url: `/pages-sub/shop/order-detail?id=${order.id}` })
}

function statusClass(status: number): string {
  if (status === 0)
    return 'status-pending'
  if (status === 1)
    return 'status-shipping'
  if (status === 2)
    return 'status-receiving'
  if (status === 3)
    return 'status-done'
  return 'status-cancel'
}
</script>

<template>
  <view class="page">
    <fg-navbar :title="$t('app.myOrders')" />

    <view class="tabs">
      <view
        v-for="(tab, idx) in tabs" :key="idx"
        class="tab-item"
        :class="idx === tabIndex ? 'tab-item-active' : ''"
        @click="onTabChange(idx)"
      >
        <text class="tab-text" :class="idx === tabIndex ? 'tab-text-active' : ''">{{ tab.name }}</text>
      </view>
    </view>

    <scroll-view scroll-y class="list">
      <view v-for="order in dataList" :key="order.id" class="order-item" @click="goDetail(order)">
        <view class="order-top">
          <text class="order-no">{{ order.order_no }}</text>
          <text class="order-status" :class="statusClass(order.status)">{{ statusText(order.status) }}</text>
        </view>
        <view class="order-main">
          <image v-if="order.cover_image !== ''" class="order-cover" :src="order.cover_image" />
          <view v-else class="order-cover order-cover-empty">
            <text class="order-cover-text">商品</text>
          </view>
          <view class="order-info">
            <text class="order-summary">{{ order.summary || '订单商品' }}</text>
            <text v-if="order.item_count > 0" class="order-count">{{ $t('app.itemsCount', { n: order.item_count }) }}</text>
          </view>
        </view>
        <view class="order-bottom">
          <text class="order-amount">¥{{ fenToYuan(order.pay_amount) }}</text>
          <text class="order-time">{{ formatTime(order.created_at) }}</text>
        </view>
      </view>
      <view v-if="!loading && dataList.length === 0" class="empty">
        <text class="empty-text">暂无订单</text>
      </view>
      <view v-if="loading" class="loading">
        <text class="loading-text">加载中...</text>
      </view>
      <view v-else-if="!hasMore && dataList.length > 0" class="loading">
        <text class="loading-text">没有更多了</text>
      </view>
    </scroll-view>
  </view>
</template>

<style scoped lang="scss">
.page {
  height: 100vh;
  display: flex;
  flex-direction: column;
  background-color: #f8f8f8;
}
.tabs {
  padding: 16rpx 16rpx 8rpx 16rpx;
  background-color: #ffffff;
  display: flex;
  flex-direction: row;
  align-items: center;
}
.tab-item {
  flex: 1;
  height: 64rpx;
  border-radius: 32rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.tab-item-active {
  background-color: #fef2f2;
}
.tab-text {
  font-size: 14px;
  color: #64748b;
}
.tab-text-active {
  color: #ef4444;
  font-weight: 700;
}
.list {
  flex: 1;
}
.order-item {
  margin: 16rpx;
  padding: 24rpx;
  background-color: #ffffff;
  border-radius: 12px;
  display: flex;
  flex-direction: column;
}
.order-top {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
}
.order-no {
  font-size: 14px;
  color: #1e293b;
  font-weight: 700;
}
.order-status {
  font-size: 13px;
  color: #ef4444;
}
.status-pending {
  color: #ef4444;
}
.status-shipping {
  color: #f59e0b;
}
.status-receiving {
  color: #0957de;
}
.status-done {
  color: #94a3b8;
}
.status-cancel {
  color: #94a3b8;
}
.order-main {
  margin-top: 16rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
}
.order-cover {
  width: 140rpx;
  height: 140rpx;
  border-radius: 12px;
  background-color: #f1f5f9;
}
.order-cover-empty {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.order-cover-text {
  font-size: 12px;
  color: #94a3b8;
}
.order-info {
  flex: 1;
  margin-left: 20rpx;
  display: flex;
  flex-direction: column;
  justify-content: center;
}
.order-summary {
  font-size: 14px;
  color: #1e293b;
}
.order-count {
  margin-top: 8rpx;
  font-size: 12px;
  color: #94a3b8;
}
.order-bottom {
  margin-top: 16rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
}
.order-amount {
  font-size: 16px;
  color: #1e293b;
  font-weight: 700;
}
.order-time {
  font-size: 12px;
  color: #94a3b8;
}
.empty {
  padding: 120rpx;
  display: flex;
  flex-direction: column;
  align-items: center;
}
.empty-text {
  font-size: 14px;
  color: #94a3b8;
}
.loading {
  padding: 24rpx;
  display: flex;
  flex-direction: row;
  justify-content: center;
}
.loading-text {
  font-size: 12px;
  color: #94a3b8;
}
</style>
