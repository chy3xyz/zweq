import { ref } from 'vue'

export interface SystemSafeAreaInsets {
  top: number
  right: number
  bottom: number
  left: number
}

export interface SystemInfoType {
  screenWidth: number
  screenHeight: number
  windowWidth: number
  windowHeight: number
  statusBarHeight: number
  pixelRatio: number
}

export const systemInfo = ref<SystemInfoType | null>(null)
export const safeAreaInsets = ref<SystemSafeAreaInsets | null>(null)

export function updateSystemInfo() {
  // #ifdef MP-WEIXIN
  const windowInfo = uni.getWindowInfo()
  systemInfo.value = {
    screenWidth: windowInfo.screenWidth,
    screenHeight: windowInfo.screenHeight,
    windowWidth: windowInfo.windowWidth,
    windowHeight: windowInfo.windowHeight,
    statusBarHeight: windowInfo.statusBarHeight ?? 0,
    pixelRatio: windowInfo.pixelRatio,
  }
  const safeArea = windowInfo.safeArea
  if (safeArea) {
    safeAreaInsets.value = {
      top: safeArea.top,
      right: windowInfo.windowWidth - safeArea.right,
      bottom: windowInfo.windowHeight - safeArea.bottom,
      left: safeArea.left,
    }
  }
  // #endif

  // #ifndef MP-WEIXIN
  const info = uni.getSystemInfoSync()
  systemInfo.value = {
    screenWidth: info.screenWidth,
    screenHeight: info.screenHeight,
    windowWidth: info.windowWidth,
    windowHeight: info.windowHeight,
    statusBarHeight: info.statusBarHeight ?? 0,
    pixelRatio: info.pixelRatio,
  }
  const inset = info.safeAreaInsets
  if (inset) {
    safeAreaInsets.value = {
      top: inset.top,
      right: inset.right,
      bottom: inset.bottom,
      left: inset.left,
    }
  }
  // #endif
}

updateSystemInfo()
