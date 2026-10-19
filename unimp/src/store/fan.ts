import { defineStore } from 'pinia'
import { computed, ref } from 'vue'

/**
 * C 端粉丝登录态。
 * 原 unix 使用 x-pinia-s，这里改用 unibest 内置的 pinia + 持久化插件，
 * 持久化 key 保持 'pinia:fan'，从 uni-app X 版本升级时可直接复用登录态。
 */
export const useFanStore = defineStore(
  'fan',
  () => {
    const fanToken = ref('')
    const openid = ref('')
    const nickname = ref('')
    const avatar = ref('')
    const points = ref(0)

    const hasLogin = computed(() => fanToken.value !== '')

    function setFanToken(token: string) {
      fanToken.value = token
    }

    function setOpenid(value: string) {
      openid.value = value
    }

    function setProfile(nickName: string, avatarUrl: string, pointsValue: number) {
      nickname.value = nickName
      avatar.value = avatarUrl
      points.value = pointsValue
    }

    function setPoints(value: number) {
      points.value = value
    }

    function clear() {
      fanToken.value = ''
      openid.value = ''
      nickname.value = ''
      avatar.value = ''
      points.value = 0
      uni.removeStorageSync('pinia:fan')
    }

    return {
      fanToken,
      openid,
      nickname,
      avatar,
      points,
      hasLogin,
      setFanToken,
      setOpenid,
      setProfile,
      setPoints,
      clear,
    }
  },
  {
    persist: {
      key: 'pinia:fan',
    },
  },
)
