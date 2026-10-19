<script setup lang="ts">
import { ref } from 'vue'
import { onLoad } from '@dcloudio/uni-app'
import { cLogin, getFanProfile, miniLogin } from '@/api/auth'
import { isDev } from '@/utils/env'
import { useFanStore } from '@/store/fan'
import { isPageTabbar, setCurIdxByPath } from '@/tabbar/store'

definePage({
  style: {
    navigationBarTitleText: '登录',
  },
})

const fanStore = useFanStore()
const redirectUrl = ref('')
const isLoggingIn = ref(false)
const testOpenid = ref('')

onLoad((options) => {
  const query = options as Record<string, string> | undefined
  if (query?.redirect) {
    redirectUrl.value = query.redirect
  }

  // #ifdef H5
  if (isDev()) {
    const cached = uni.getStorageSync('test_openid')
    testOpenid.value = (cached && typeof cached === 'string') ? cached : `dev_${Date.now()}`
  }
  // #endif
})

/** 登录成功后统一跳转：优先回 redirect，否则返回上一页 */
function redirectAfterLogin() {
  if (redirectUrl.value !== '') {
    const targetUrl = decodeURIComponent(redirectUrl.value)
    if (isPageTabbar(targetUrl)) {
      setCurIdxByPath(targetUrl)
      uni.switchTab({ url: targetUrl })
    }
    else {
      uni.redirectTo({ url: targetUrl })
    }
  }
  else {
    uni.navigateBack()
  }
}

function doLogin() {
  if (fanStore.hasLogin) {
    redirectAfterLogin()
    return
  }

  // #ifdef MP-WEIXIN
  uni.login({
    success: (res) => {
      const code = res.code
      // code → openid → fan token
      miniLogin(code).then((miniRes) => {
        fanStore.setOpenid(miniRes.openid)
        return cLogin(miniRes.openid)
      }).then((loginRes) => {
        fanStore.setFanToken(loginRes.token)
        uni.showToast({ title: '登录成功', icon: 'success' })
        setTimeout(() => {
          redirectAfterLogin()
        }, 800)
        getFanProfile().then((profile) => {
          fanStore.setProfile(profile.nickname, profile.avatar, profile.points)
        }).catch(() => {})
      }).catch(() => {
        uni.showToast({ title: '登录失败', icon: 'none' })
      })
    },
    fail: () => {
      uni.showToast({ title: '微信登录失败', icon: 'none' })
    },
  })
  // #endif
}

// #ifdef H5
function doTestLogin() {
  if (!isDev()) {
    uni.showToast({ title: '当前环境不可用', icon: 'none' })
    return
  }

  if (fanStore.hasLogin) {
    redirectAfterLogin()
    return
  }

  const openid = testOpenid.value.trim()
  if (openid === '') {
    uni.showToast({ title: '请输入 openid', icon: 'none' })
    return
  }

  if (isLoggingIn.value)
    return

  isLoggingIn.value = true
  cLogin(openid).then((loginRes) => {
    isLoggingIn.value = false
    fanStore.setOpenid(openid)
    fanStore.setFanToken(loginRes.token)
    uni.setStorageSync('test_openid', openid)
    uni.showToast({ title: '登录成功', icon: 'success' })
    setTimeout(() => {
      redirectAfterLogin()
    }, 800)
    getFanProfile().then((profile) => {
      fanStore.setProfile(profile.nickname, profile.avatar, profile.points)
    }).catch(() => {})
  }).catch(() => {
    isLoggingIn.value = false
    uni.showToast({ title: '登录失败', icon: 'none' })
  })
}
// #endif
</script>

<template>
  <view class="page">
    <view class="brand">
      <view class="brand-logo">
        <text class="brand-logo-text">Z</text>
      </view>
      <text class="brand-name">ZWEQ</text>
      <text class="brand-sub">多商户微信运营平台</text>
    </view>

    <view class="login-card">
      <text class="card-title">登录账号</text>

      <!-- #ifdef MP-WEIXIN -->
      <view class="btn-primary" @click="doLogin">
        <text class="btn-text">{{ $t('app.wechatLogin') }}</text>
      </view>
      <text class="card-tip">使用微信授权登录，首次登录会自动创建粉丝账号</text>
      <!-- #endif -->

      <!-- #ifdef H5 -->
      <view v-if="isDev" class="form">
        <input
          v-model="testOpenid"
          class="input"
          placeholder="请输入测试 openid"
          placeholder-style="color: #94a3b8"
        >
        <view class="btn-primary" :class="{ 'btn-disabled': isLoggingIn }" @click="doTestLogin">
          <text class="btn-text">{{ isLoggingIn ? '登录中…' : '测试账号登录' }}</text>
        </view>
        <text class="tip">本地开发可填写任意 openid，后端会按 account_id 创建/复用粉丝</text>
      </view>
      <!-- #endif -->
    </view>

    <text class="footer">ZWEQ · powered by unibest</text>
  </view>
</template>

<style scoped lang="scss">
.page {
  min-height: 100vh;
  padding: 80rpx 48rpx 48rpx 48rpx;
  box-sizing: border-box;
  display: flex;
  flex-direction: column;
  align-items: center;
  background-color: var(--z-bg, #f5f7fb);
}
.brand {
  display: flex;
  flex-direction: column;
  align-items: center;
}
.brand-logo {
  width: 120rpx;
  height: 120rpx;
  border-radius: 32rpx;
  background-image: linear-gradient(160deg, var(--theme-color, #0957de), #4f7cff);
  box-shadow: 0 16rpx 40rpx rgba(9, 87, 222, 0.28);
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.brand-logo-text {
  font-size: 56rpx;
  color: #ffffff;
  font-weight: 800;
}
.brand-name {
  margin-top: 24rpx;
  font-size: 44rpx;
  font-weight: 800;
  letter-spacing: 4rpx;
  color: var(--z-text, #0f172a);
}
.brand-sub {
  margin-top: 10rpx;
  font-size: 24rpx;
  color: var(--z-muted, #94a3b8);
}
.login-card {
  width: 100%;
  margin-top: 64rpx;
  padding: 40rpx 32rpx;
  box-sizing: border-box;
  background-color: #ffffff;
  border-radius: 32rpx;
  box-shadow: var(--z-shadow, 0 10rpx 36rpx rgba(15, 23, 42, 0.06));
  display: flex;
  flex-direction: column;
}
.card-title {
  font-size: 32rpx;
  font-weight: 700;
  color: var(--z-text, #0f172a);
}
.form {
  width: 100%;
  margin-top: 28rpx;
  display: flex;
  flex-direction: column;
}
.input {
  width: 100%;
  height: 92rpx;
  padding: 0 28rpx;
  border-radius: 20rpx;
  background-color: #f5f7fb;
  font-size: 28rpx;
  color: var(--z-text, #0f172a);
  margin-bottom: 28rpx;
  box-sizing: border-box;
}
.btn-primary {
  width: 100%;
  height: 92rpx;
  margin-top: 28rpx;
  border-radius: 46rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.btn-disabled {
  opacity: 0.5;
}
.btn-text {
  color: #ffffff;
  font-size: 30rpx;
  font-weight: 700;
}
.card-tip {
  margin-top: 24rpx;
  font-size: 24rpx;
  color: var(--z-muted, #94a3b8);
}
.tip {
  margin-top: 20rpx;
  font-size: 22rpx;
  color: var(--z-muted, #94a3b8);
  text-align: center;
}
.footer {
  margin-top: auto;
  padding-top: 60rpx;
  font-size: 22rpx;
  color: #cbd5e1;
}
</style>
