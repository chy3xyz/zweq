<script setup lang="ts">
import { ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import type { IAddress } from '@/api/shop'
import { listAddresses } from '@/api/shop'
import { useFanStore } from '@/store/fan'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '收货地址',
  },
})

const fanStore = useFanStore()
const addresses = ref<IAddress[]>([])

async function loadAddresses() {
  try {
    addresses.value = await listAddresses(fanStore.openid)
  }
  catch (err) {
    console.error('loadAddresses error:', err)
  }
}

function selectAddress(address: IAddress) {
  uni.setStorageSync('selectedAddress', JSON.stringify(address))
  uni.navigateBack()
}

function goAdd() {
  uni.navigateTo({ url: '/pages-sub/shop/address-edit' })
}

onShow(() => {
  loadAddresses()
})
</script>

<template>
  <view class="page-root">
    <fg-navbar title="收货地址">
      <template #right>
        <view class="nav-add" @click="goAdd">
          <text class="nav-add-text">新增</text>
        </view>
      </template>
    </fg-navbar>

    <scroll-view scroll-y class="main">
      <view v-if="addresses.length === 0" class="empty">
        <text class="empty-text">暂无收货地址</text>
      </view>
      <view v-else class="list">
        <view v-for="it in addresses" :key="it.id" class="addr-item" @click="selectAddress(it)">
          <view class="addr-top">
            <text class="addr-name">{{ it.name }}</text>
            <text class="addr-mobile">{{ it.mobile }}</text>
            <view v-if="it.is_default === 1" class="addr-tag">
              <text class="addr-tag-text">默认</text>
            </view>
          </view>
          <text class="addr-region">{{ it.region }}{{ it.detail }}</text>
        </view>
      </view>
    </scroll-view>

    <view class="footer">
      <view class="btn-add" @click="goAdd">
        <text class="btn-add-text">新增收货地址</text>
      </view>
    </view>
  </view>
</template>

<style scoped lang="scss">
.page-root {
  height: 100vh;
  display: flex;
  flex-direction: column;
  background-color: #f8f8f8;
}
.main {
  flex: 1;
}
.nav-add {
  padding: 6rpx 4rpx;
}
.nav-add-text {
  font-size: 15px;
  color: #ef4444;
}
.list {
  padding: 16rpx;
}
.addr-item {
  margin-bottom: 16rpx;
  padding: 24rpx;
  background-color: #ffffff;
  border-radius: 12px;
  display: flex;
  flex-direction: column;
}
.addr-top {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: flex-start;
}
.addr-name {
  font-size: 16px;
  color: #1e293b;
  font-weight: 700;
}
.addr-mobile {
  margin-left: 16rpx;
  font-size: 14px;
  color: #64748b;
}
.addr-tag {
  margin-left: 12rpx;
  padding: 2rpx 12rpx;
  border-radius: 6px;
  background-color: #fef2f2;
}
.addr-tag-text {
  font-size: 12px;
  color: #ef4444;
}
.addr-region {
  margin-top: 12rpx;
  font-size: 14px;
  color: #475569;
  line-height: 20px;
}
.empty {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 80rpx;
}
.empty-text {
  font-size: 14px;
  color: #94a3b8;
}
.footer {
  padding: 16rpx 24rpx;
  background-color: #ffffff;
}
.btn-add {
  height: 80rpx;
  border-radius: 40rpx;
  background-color: var(--theme-color, #0957de);
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.btn-add-text {
  font-size: 15px;
  color: #ffffff;
  font-weight: 700;
}
</style>
