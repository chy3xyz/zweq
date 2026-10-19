<script setup lang="ts">
import { computed } from 'vue'
import { safeAreaInsets, systemInfo } from '@/utils/systemInfo'

const props = withDefaults(defineProps<{
  title?: string
  titleColor?: string
  bgColor?: string
  showBack?: boolean
  fixed?: boolean
  placeholder?: boolean
  border?: boolean
}>(), {
  title: '',
  titleColor: '#1e293b',
  bgColor: '#ffffff',
  showBack: true,
  fixed: true,
  placeholder: true,
  border: false,
})

/** 状态栏高度：优先安全区 top，再取系统状态栏高度 */
const statusBarHeight = computed(() => {
  return safeAreaInsets.value?.top ?? systemInfo.value?.statusBarHeight ?? 0
})

function handleBack() {
  uni.navigateBack({
    fail() {
      uni.switchTab({ url: '/pages/index/index' })
    },
  })
}
</script>

<template>
  <view>
    <view
      :class="fixed ? 'navbar-container navbar-fixed app-fixed-bar' : 'navbar-container'"
      :style="{ backgroundColor: bgColor, borderBottom: border ? '1px solid #e2e8f0' : 'none' }"
    >
      <view :style="{ height: `${statusBarHeight}px` }" />

      <view class="navbar-content">
        <view class="navbar-left" @click="handleBack">
          <slot name="left">
            <view v-if="showBack" class="back-btn-wrapper">
              <view class="back-arrow" :style="{ borderColor: titleColor }" />
            </view>
          </slot>
        </view>

        <view class="navbar-title">
          <slot>
            <text class="title-text" :style="{ color: titleColor }">{{ props.title }}</text>
          </slot>
        </view>

        <view class="navbar-right">
          <slot name="right" />
        </view>
      </view>
    </view>

    <view v-if="fixed && placeholder" :style="{ height: `${statusBarHeight + 44}px` }" />
  </view>
</template>

<style scoped lang="scss">
.navbar-container {
  width: 100%;
  display: flex;
  flex-direction: column;
}
.navbar-fixed {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  z-index: 999;
}
.navbar-content {
  height: 44px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  position: relative;
  width: 100%;
}
.navbar-left {
  position: absolute;
  left: 0;
  top: 0;
  bottom: 0;
  width: 60px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: flex-start;
  z-index: 10;
}
.back-btn-wrapper {
  padding: 10px 15px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
}
.back-arrow {
  width: 10px;
  height: 10px;
  border-left: 2px solid #1e293b;
  border-bottom: 2px solid #1e293b;
  transform: rotate(45deg);
}
.navbar-title {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  flex: 1;
  height: 100%;
  padding-left: 60px;
  padding-right: 60px;
}
.title-text {
  font-size: 16px;
  font-weight: 700;
  text-overflow: ellipsis;
  overflow: hidden;
  white-space: nowrap;
}
.navbar-right {
  position: absolute;
  right: 0;
  top: 0;
  bottom: 0;
  width: 60px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: flex-end;
  z-index: 10;
  padding-right: 15px;
}
</style>
