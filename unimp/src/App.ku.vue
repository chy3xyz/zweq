<script setup lang="ts">
import { computed, ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import FgTabbar from '@/tabbar/index.vue'
import { isPageTabbar } from '@/tabbar/store'
import { useAppStore } from '@/store/app'
import { currRoute } from '@/utils'

const appStore = useAppStore()
const themeColor = computed(() => appStore.theme)

/** 当前页是否 tabbar 页：决定是否渲染底栏与 AI 浮动入口 */
const isCurrentPageTabbar = ref(false)
const showAiFloat = ref(false)

onShow(() => {
  const { path } = currRoute()
  isCurrentPageTabbar.value = path === '/' ? true : isPageTabbar(path)
  // 购物车底部有结算栏，浮动入口会挡住按钮，故单独隐藏
  showAiFloat.value = isCurrentPageTabbar.value && path !== '/pages/cart/cart'

  // #ifndef MP-WEIXIN
  // H5 / App 端 custom:true 不会自动隐藏原生 tabbar，这里手动隐藏，
  // 否则会和 App.ku 中渲染的自定义 tabbar 叠成两层。
  uni.hideTabBar({
    fail() {
      // 非 tabbar 页面调用会失败，忽略
    },
  })
  // #endif
})

/** AI 助手全局浮动入口（仅 tab 页显示） */
function goAi() {
  uni.navigateTo({ url: '/pages/ai/ai' })
}
</script>

<template>
  <view class="app-root" :style="{ '--theme-color': themeColor }">
    <KuRootView />

    <FgTabbar v-if="isCurrentPageTabbar" />

    <view v-if="showAiFloat" class="ai-float app-fixed-float" @click="goAi">
      <text class="ai-float-icon">🤖</text>
    </view>
  </view>
</template>

<style>
.app-root {
  --theme-color: #0957de;
}

.ai-float {
  position: fixed;
  right: 30rpx;
  bottom: 170rpx;
  width: 108rpx;
  height: 108rpx;
  border-radius: 54rpx;
  background-color: var(--theme-color, #0957de);
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  z-index: 999;
  box-shadow: 0 8rpx 24rpx rgba(9, 87, 222, 0.4);
}

.ai-float-icon {
  font-size: 48rpx;
  line-height: 1;
}
</style>
