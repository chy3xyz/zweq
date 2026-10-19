<script setup lang="ts">
import { ref } from 'vue'
import type { IAddressInput } from '@/api/shop'
import { createAddress } from '@/api/shop'
import { useFanStore } from '@/store/fan'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '编辑地址',
  },
})

const fanStore = useFanStore()
const name = ref('')
const mobile = ref('')
const region = ref('')
const detail = ref('')
const isDefault = ref(0)

function toggleDefault() {
  isDefault.value = isDefault.value === 1 ? 0 : 1
}

function submit() {
  if (name.value === '' || mobile.value === '' || detail.value === '') {
    uni.showToast({ title: '请填写完整信息', icon: 'none' })
    return
  }
  const addr: IAddressInput = {
    openid: fanStore.openid,
    name: name.value,
    mobile: mobile.value,
    region: region.value,
    detail: detail.value,
    is_default: isDefault.value,
  }
  createAddress(addr).then(() => {
    uni.showToast({ title: '保存成功', icon: 'success' })
    setTimeout(() => {
      uni.navigateBack()
    }, 600)
  })
}
</script>

<template>
  <view class="page-root">
    <fg-navbar title="编辑地址" />

    <scroll-view scroll-y class="main">
      <view class="form">
        <view class="form-item">
          <text class="form-label">收货人</text>
          <input v-model="name" class="form-input" placeholder="请输入收货人姓名" placeholder-style="color: #cbd5e1">
        </view>
        <view class="form-item">
          <text class="form-label">手机号</text>
          <input v-model="mobile" type="number" :maxlength="11" class="form-input" placeholder="请输入手机号" placeholder-style="color: #cbd5e1">
        </view>
        <view class="form-item">
          <text class="form-label">所在地区</text>
          <input v-model="region" class="form-input" placeholder="请输入省市区" placeholder-style="color: #cbd5e1">
        </view>
        <view class="form-item">
          <text class="form-label">详细地址</text>
          <input v-model="detail" class="form-input" placeholder="街道、门牌号等" placeholder-style="color: #cbd5e1">
        </view>
        <view class="form-item">
          <text class="form-label">设为默认</text>
          <view class="switch-area" @click="toggleDefault">
            <view class="switch-box" :class="isDefault === 1 ? 'switch-on' : ''">
              <view class="switch-dot" :class="isDefault === 1 ? 'dot-on' : ''" />
            </view>
          </view>
        </view>
      </view>
    </scroll-view>

    <view class="footer">
      <view class="btn-submit" @click="submit">
        <text class="btn-submit-text">保存地址</text>
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
.form {
  margin: 16rpx;
  padding: 8rpx 24rpx;
  background-color: #ffffff;
  border-radius: 12px;
  display: flex;
  flex-direction: column;
}
.form-item {
  height: 100rpx;
  border-bottom-width: 1px;
  border-bottom-color: #f1f5f9;
  border-bottom-style: solid;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: flex-start;
}
.form-label {
  width: 160rpx;
  font-size: 14px;
  color: #1e293b;
}
.form-input {
  flex: 1;
  font-size: 14px;
  color: #1e293b;
}
.switch-area {
  flex: 1;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: flex-end;
}
.switch-box {
  width: 88rpx;
  height: 48rpx;
  border-radius: 24rpx;
  background-color: #e2e8f0;
  display: flex;
  flex-direction: row;
  align-items: center;
  padding: 0 4rpx;
  box-sizing: border-box;
}
.switch-on {
  background-color: var(--theme-color, #0957de);
}
.switch-dot {
  width: 40rpx;
  height: 40rpx;
  border-radius: 20rpx;
  background-color: #ffffff;
}
.dot-on {
  transform: translateX(40rpx);
}
.footer {
  padding: 16rpx 24rpx;
  background-color: #ffffff;
}
.btn-submit {
  height: 80rpx;
  border-radius: 40rpx;
  background-color: var(--theme-color, #0957de);
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.btn-submit-text {
  font-size: 15px;
  color: #ffffff;
  font-weight: 700;
}
</style>
