<script setup lang="ts">
import { computed, ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import { getMemberCard } from '@/api/marketing'
import { useFanStore } from '@/store/fan'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '个人信息',
  },
})

const fanStore = useFanStore()
const memberTag = ref('普通会员')

const avatarUrl = computed(() => fanStore.avatar !== '' ? fanStore.avatar : '/static/logo.png')
const nickname = computed(() => fanStore.nickname !== '' ? fanStore.nickname : '微信用户')
const openid = computed(() => fanStore.openid)
const points = computed(() => fanStore.points)

onShow(() => {
  if (fanStore.hasLogin) {
    getMemberCard().then((m) => {
      if (m)
        memberTag.value = m.level_name
    }).catch(() => {})
  }
})

function previewAvatar() {
  if (avatarUrl.value !== '') {
    uni.previewImage({ urls: [avatarUrl.value] })
  }
}

function copyOpenid() {
  uni.setClipboardData({
    data: openid.value,
    success: () => {
      uni.showToast({ title: 'openid 已复制', icon: 'success' })
    },
  })
}
</script>

<template>
  <view class="page">
    <fg-navbar title="个人信息" />

    <scroll-view scroll-y class="main">
      <view class="profile-head">
        <image class="avatar" :src="avatarUrl" @click="previewAvatar" />
        <text class="nickname">{{ nickname }}</text>
        <text v-if="fanStore.hasLogin" class="member-tag">{{ memberTag }}</text>
      </view>

      <view class="card">
        <view class="info-row">
          <text class="info-label">我的积分</text>
          <text class="info-value">{{ points }}</text>
        </view>
        <view class="info-row">
          <text class="info-label">会员等级</text>
          <text class="info-value">{{ memberTag }}</text>
        </view>
        <view class="info-row">
          <text class="info-label">openid</text>
          <view class="info-value-row">
            <text class="info-value">{{ openid }}</text>
            <view class="copy-btn" @click="copyOpenid">
              <text class="copy-btn-text">复制</text>
            </view>
          </view>
        </view>
      </view>

      <view class="tip">
        <text class="tip-text">昵称与头像来自微信授权，可在微信中修改后重新进入同步</text>
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
.main {
  flex: 1;
}
.profile-head {
  padding: 48rpx 24rpx;
  display: flex;
  flex-direction: column;
  align-items: center;
  background-image: linear-gradient(135deg, var(--theme-color, #0957de), #1890ff);
}
.avatar {
  width: 140rpx;
  height: 140rpx;
  border-radius: 70rpx;
  border-width: 3rpx;
  border-style: solid;
  border-color: rgba(255, 255, 255, 0.6);
}
.nickname {
  margin-top: 20rpx;
  font-size: 17px;
  color: #ffffff;
  font-weight: 700;
}
.member-tag {
  margin-top: 12rpx;
  padding: 4rpx 20rpx;
  border-radius: 20rpx;
  background-color: rgba(255, 255, 255, 0.22);
  font-size: 12px;
  color: #ffffff;
}
.card {
  margin: 24rpx;
  padding: 24rpx;
  background-color: #ffffff;
  border-radius: 12px;
  display: flex;
  flex-direction: column;
}
.info-row {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  padding: 20rpx 0;
  border-bottom-width: 1px;
  border-bottom-style: solid;
  border-bottom-color: #f1f5f9;
}
.info-label {
  font-size: 14px;
  color: #64748b;
}
.info-value {
  font-size: 14px;
  color: #1e293b;
  font-weight: 600;
}
.info-value-row {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: flex-end;
}
.copy-btn {
  margin-left: 16rpx;
  padding: 8rpx 20rpx;
  border-radius: 20rpx;
  background-color: var(--theme-color, #0957de);
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.copy-btn-text {
  font-size: 12px;
  color: #ffffff;
  font-weight: 700;
}
.tip {
  margin: 0 24rpx;
}
.tip-text {
  font-size: 12px;
  color: #94a3b8;
}
</style>
