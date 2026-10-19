<script setup lang="ts">
import { LOGIN_PAGE } from '@/router/config'

definePage({
  style: {
    navigationBarTitleText: '注册',
  },
})

function doRegister() {
  uni.showToast({ title: '注册成功', icon: 'success' })
  setTimeout(() => {
    uni.navigateTo({ url: LOGIN_PAGE })
  }, 1000)
}
</script>

<template>
  <view class="page">
    <view class="title-wrap">
      <text class="title">注册页</text>
    </view>
    <view class="btn" @click="doRegister">
      <text class="btn-text">点击模拟注册</text>
    </view>
  </view>
</template>

<style scoped lang="scss">
.page {
  min-height: 100vh;
  padding: 60rpx;
  box-sizing: border-box;
  display: flex;
  flex-direction: column;
  align-items: center;
  background-color: #f8f8f8;
}
.title-wrap {
  margin-bottom: 60rpx;
}
.title {
  font-size: 20px;
  font-weight: 700;
  color: #1e293b;
}
.btn {
  width: 400rpx;
  height: 88rpx;
  border-radius: 8px;
  background-color: #10b981;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.btn-text {
  color: #ffffff;
  font-size: 14px;
  font-weight: 700;
}
</style>
