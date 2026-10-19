<script setup lang="ts">
import { computed, ref } from 'vue'
import { onLoad } from '@dcloudio/uni-app'
import type { IOrderDetail, IRefund } from '@/api/shop'
import { applyRefund, cancelOrder, confirmOrder, getOrderDetail, getOrderPayParams, listRefunds, payComplete } from '@/api/shop'
import { t } from '@/i18n'
import { useFanStore } from '@/store/fan'
import { fenToYuan, formatTime } from '@/utils/format'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '订单详情',
  },
})

const fanStore = useFanStore()
const orderId = ref(0)
const detail = ref<IOrderDetail | null>(null)
const shouldAutoPay = ref(false)
const refunds = ref<IRefund[]>([])
const orderItems = computed(() => detail.value?.items ?? [])

onLoad((options) => {
  const query = options as Record<string, string> | undefined
  if (!query?.id)
    return
  orderId.value = Number.parseInt(query.id)
  shouldAutoPay.value = query.pay === '1'
  load()
})

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

function load() {
  getOrderDetail(orderId.value).then((res) => {
    detail.value = res
    loadRefunds()
    if (shouldAutoPay.value && res.order.status === 0) {
      shouldAutoPay.value = false
      pay()
    }
  }).catch(() => {
    uni.showToast({ title: '订单加载失败', icon: 'none' })
  })
}

function loadRefunds() {
  listRefunds(orderId.value).then((list) => {
    refunds.value = list
  }).catch(() => {
    refunds.value = []
  })
}

function pay() {
  getOrderPayParams(orderId.value).then((params) => {
    if (params.mode === 'wxpay_v3') {
      // #ifdef MP-WEIXIN
      uni.requestPayment({
        provider: 'wxpay',
        timeStamp: params.payment.timeStamp,
        nonceStr: params.payment.nonceStr,
        package: params.payment.package,
        signType: params.payment.signType,
        paySign: params.payment.paySign,
        success: () => {
          uni.showToast({ title: '支付成功', icon: 'success' })
          load()
        },
        fail: () => {
          uni.showToast({ title: '支付取消', icon: 'none' })
        },
      } as unknown as UniApp.RequestPaymentOptions)
      // #endif
      // #ifndef MP-WEIXIN
      uni.showToast({ title: '请在微信小程序内完成支付', icon: 'none' })
      // #endif
    }
    else {
      payComplete(orderId.value).then(() => {
        uni.showToast({ title: '支付成功', icon: 'success' })
        load()
      }).catch(() => {
        uni.showToast({ title: '支付失败', icon: 'none' })
      })
    }
  }).catch(() => {
    uni.showToast({ title: '获取支付参数失败', icon: 'none' })
  })
}

function onCancel() {
  cancelOrder(orderId.value).then(() => {
    uni.showToast({ title: '已取消', icon: 'success' })
    load()
  }).catch(() => {
    uni.showToast({ title: '取消失败', icon: 'none' })
  })
}

function onConfirm() {
  confirmOrder(orderId.value).then(() => {
    uni.showToast({ title: '已确认收货', icon: 'success' })
    load()
  }).catch(() => {
    uni.showToast({ title: '操作失败', icon: 'none' })
  })
}

function onApplyRefund() {
  uni.showModal({
    title: '申请退款',
    content: '确认申请退款？',
    success: (res) => {
      if (res.confirm) {
        applyRefund(orderId.value, fanStore.openid, '不想要了').then(() => {
          uni.showToast({ title: '退款申请已提交', icon: 'success' })
          load()
        }).catch(() => {
          uni.showToast({ title: '退款申请失败', icon: 'none' })
        })
      }
    },
  })
}
</script>

<template>
  <view class="page">
    <fg-navbar title="订单详情" />
    <scroll-view scroll-y class="main">
      <view v-if="detail" class="content">
        <view class="card status-card">
          <text class="status-text">{{ statusText(detail.order.status) }}</text>
          <text class="status-amount">¥{{ fenToYuan(detail.order.pay_amount) }}</text>
        </view>

        <view class="card">
          <text class="info-line">{{ $t('app.orderNo') }}：{{ detail.order.order_no }}</text>
          <text class="info-line">{{ $t('app.createdAt') }}：{{ formatTime(detail.order.created_at) }}</text>
        </view>

        <view v-if="detail.order.express_company !== '' || detail.order.express_no !== ''" class="card">
          <text class="section-title">{{ $t('app.shippingInfo') }}</text>
          <text class="info-line">{{ $t('app.shippingCompany') }}：{{ detail.order.express_company }}</text>
          <text class="info-line">{{ $t('app.trackingNo') }}：{{ detail.order.express_no }}</text>
        </view>

        <view class="card">
          <text class="section-title">{{ $t('app.goodsList') }}</text>
          <text v-if="orderItems.length === 0" class="info-line">暂无商品明细</text>
          <view v-for="(it, idx) in orderItems" :key="idx" class="goods-item">
            <image class="goods-img" :src="it.image" />
            <view class="goods-info">
              <text class="goods-name">{{ it.name }}</text>
              <view class="goods-bottom">
                <text class="goods-price">¥{{ fenToYuan(it.price) }}</text>
                <text class="goods-qty">x{{ it.quantity }}</text>
              </view>
            </view>
          </view>
        </view>

        <view v-if="refunds.length > 0" class="card">
          <text class="section-title">{{ $t('app.refundRecord') }}</text>
          <view v-for="(r, idx) in refunds" :key="idx" class="refund-item">
            <text class="refund-reason">{{ r.reason }}</text>
            <text class="refund-time">{{ formatTime(r.created_at) }}</text>
          </view>
        </view>
      </view>
      <view v-else class="empty">
        <text class="empty-text">{{ $t('app.orderNotFound') }}</text>
      </view>
    </scroll-view>

    <view v-if="detail && detail.order.status === 0" class="footer">
      <view class="btn-cancel" @click="onCancel">
        <text class="btn-cancel-text">{{ $t('app.cancelOrder') }}</text>
      </view>
      <view class="btn-primary" @click="pay">
        <text class="btn-primary-text">{{ $t('app.goPay') }}</text>
      </view>
    </view>
    <view v-else-if="detail && detail.order.status === 1" class="footer">
      <view class="btn-cancel" @click="onApplyRefund">
        <text class="btn-cancel-text">{{ $t('app.refund') }}</text>
      </view>
    </view>
    <view v-else-if="detail && detail.order.status === 2" class="footer">
      <view class="btn-cancel" @click="onApplyRefund">
        <text class="btn-cancel-text">{{ $t('app.refund') }}</text>
      </view>
      <view class="btn-primary" @click="onConfirm">
        <text class="btn-primary-text">{{ $t('app.confirmReceipt') }}</text>
      </view>
    </view>
  </view>
</template>

<style scoped lang="scss">
.page {
  height: 100vh;
  display: flex;
  flex-direction: column;
  background-color: #f8f8f8;
}
.main {
  flex: 1;
}
.content {
  display: flex;
  flex-direction: column;
}
.card {
  margin: 16rpx;
  padding: 24rpx;
  background-color: #ffffff;
  border-radius: 12px;
  display: flex;
  flex-direction: column;
}
.status-card {
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
}
.status-text {
  font-size: 17px;
  color: #1e293b;
  font-weight: 700;
}
.status-amount {
  font-size: 20px;
  color: #ef4444;
  font-weight: 700;
}
.info-line {
  margin-top: 8rpx;
  font-size: 14px;
  color: #475569;
}
.section-title {
  font-size: 15px;
  color: #1e293b;
  font-weight: 700;
}
.goods-item {
  margin-top: 16rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
}
.goods-img {
  width: 120rpx;
  height: 120rpx;
  border-radius: 8px;
}
.goods-info {
  flex: 1;
  margin-left: 20rpx;
  display: flex;
  flex-direction: column;
}
.goods-name {
  font-size: 14px;
  color: #1e293b;
}
.goods-bottom {
  margin-top: 12rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
}
.goods-price {
  font-size: 15px;
  color: #ef4444;
  font-weight: 700;
}
.goods-qty {
  font-size: 13px;
  color: #64748b;
}
.refund-item {
  margin-top: 16rpx;
  padding: 16rpx;
  background-color: #f8fafc;
  border-radius: 8px;
  display: flex;
  flex-direction: column;
}
.refund-reason {
  font-size: 14px;
  color: #1e293b;
}
.refund-time {
  margin-top: 8rpx;
  font-size: 12px;
  color: #94a3b8;
}
.empty {
  padding: 80rpx;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
}
.empty-text {
  font-size: 14px;
  color: #94a3b8;
}
.footer {
  height: 100rpx;
  padding: 0 24rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: flex-end;
  background-color: #ffffff;
}
.btn-cancel {
  height: 72rpx;
  padding: 0 40rpx;
  border-radius: 36rpx;
  border-width: 1px;
  border-color: #cbd5e1;
  border-style: solid;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.btn-cancel-text {
  font-size: 14px;
  color: #475569;
}
.btn-primary {
  height: 72rpx;
  margin-left: 16rpx;
  padding: 0 40rpx;
  border-radius: 36rpx;
  background-color: var(--theme-color, #0957de);
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.btn-primary-text {
  font-size: 14px;
  color: #ffffff;
  font-weight: 700;
}
</style>
