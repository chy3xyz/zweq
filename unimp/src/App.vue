<script setup lang="ts">
import { onHide, onLaunch, onShow } from '@dcloudio/uni-app'
import { navigateToInterceptor } from '@/router/interceptor'

onLaunch(() => {
  console.log('ZWEQ App Launch')
})

onShow((options) => {
  // 处理直接进入页面（H5 直链、小程序分享进入等）时的 tabbar 同步
  if (options?.path) {
    navigateToInterceptor.invoke({ url: `/${options.path}` })
  }
  else {
    navigateToInterceptor.invoke({ url: '/' })
  }
})

onHide(() => {
  console.log('ZWEQ App Hide')
})
</script>

<style lang="scss">
page {
  --z-bg: #f5f7fb;
  --z-card: #ffffff;
  --z-text: #0f172a;
  --z-text-2: #475569;
  --z-muted: #94a3b8;
  --z-line: #eef2f7;
  --z-primary: var(--theme-color, #0957de);
  --z-primary-2: #4f7cff;
  --z-radius: 24rpx;
  --z-shadow: 0 10rpx 36rpx rgba(15, 23, 42, 0.06);

  background-color: var(--z-bg);
  color: var(--z-text);
  font-size: 28rpx;
}

/* ===== 业务页通用骨架 ===== */
.z-page {
  height: 100vh;
  display: flex;
  flex-direction: column;
  background-color: var(--z-bg);
}
.z-body {
  flex: 1;
}
.z-card {
  background-color: var(--z-card);
  border-radius: var(--z-radius);
  box-shadow: var(--z-shadow);
}
.z-title {
  font-size: 34rpx;
  font-weight: 700;
  color: var(--z-text);
}
.z-muted {
  color: var(--z-muted);
}

/* ===== 统一卡片阴影（页面 scoped 样式不重复写 shadow） ===== */
.card,
.goods-card,
.order-item,
.addr-item,
.coupon-card,
.plan-card,
.record-card,
.vote-card,
.seckill-card,
.stat-card,
.withdraw-card,
.join-card,
.member-card,
.empty-card,
.asset-card,
.status-card,
.refund-item,
.product-card,
.order-card {
  box-shadow: var(--z-shadow);
}

/* ===== 主按钮统一渐变 / 阴影 ===== */
.btn-primary,
.btn-submit,
.btn-add,
.btn-pay,
.btn-confirm,
.btn-buy,
.go-shopping-btn,
.draw-btn,
.claim-btn,
.rush-btn,
.recharge-btn,
.open-btn,
.join-btn,
.withdraw-btn,
.invite-btn,
.copy-btn,
.comment-btn,
.send-btn,
.search-btn {
  background-image: linear-gradient(135deg, var(--z-primary), var(--z-primary-2));
  box-shadow: 0 10rpx 24rpx rgba(9, 87, 222, 0.22);
}
.btn-primary:active,
.btn-submit:active,
.btn-add:active,
.btn-pay:active,
.btn-confirm:active,
.btn-buy:active,
.draw-btn:active,
.claim-btn:active,
.rush-btn:active,
.recharge-btn:active,
.open-btn:active,
.join-btn:active,
.withdraw-btn:active,
.invite-btn:active,
.copy-btn:active,
.comment-btn:active,
.send-btn:active,
.search-btn:active {
  opacity: 0.88;
}

/* ===== H5 桌面端：430px 手机预览框 ===== */
/* #ifdef H5 */
@media (min-width: 640px) {
  body {
    background: radial-gradient(circle at 50% 0%, #f6f8fc 0%, #e7ecf4 60%, #dfe6f0 100%);
  }
  uni-app {
    background: transparent;
  }
  .app-root {
    width: 430px;
    max-width: 430px;
    margin: 0 auto;
    min-height: 100vh;
    background-color: var(--z-bg);
    box-shadow: 0 0 70px rgba(15, 23, 42, 0.14);
    border-left: 1px solid rgba(15, 23, 42, 0.04);
    border-right: 1px solid rgba(15, 23, 42, 0.04);
  }
  .app-fixed-bar {
    left: 50% !important;
    right: auto !important;
    width: 430px !important;
    box-sizing: border-box !important;
    transform: translateX(-50%);
  }
  .app-fixed-float {
    right: calc((100vw - 430px) / 2 + 15px) !important;
  }
  uni-page-head {
    left: auto !important;
    right: auto !important;
    width: 430px !important;
    margin: 0 auto !important;
    transform: none !important;
  }
  uni-page-head .uni-page-head {
    left: calc(50% - 215px) !important;
    right: auto !important;
    width: 430px !important;
    transform: none !important;
  }
}
/* #endif */
</style>
