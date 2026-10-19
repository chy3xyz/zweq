import { createPinia, setActivePinia } from 'pinia'
import { createPersistedState } from 'pinia-plugin-persistedstate'

const store = createPinia()
store.use(
  createPersistedState({
    storage: {
      getItem: uni.getStorageSync,
      setItem: uni.setStorageSync,
    },
  }),
)
// 立即激活 Pinia 实例，这样即使在 app.use(store) 之前调用 store 也能工作（解决 APP 端白屏）
setActivePinia(store)

export default store

// 模块统一导出（ZWEQ C 端只需要 app / fan）
export * from './app'
export * from './fan'
