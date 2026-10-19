<script setup lang="ts">
import { computed, ref } from 'vue'
import { onLoad, onShareAppMessage, onShow } from '@dcloudio/uni-app'
import type { IGroupon, IProductDetail, ISku } from '@/api/shop'
import { addCart, addFavorite, deleteFavorite, getProductDetail, listAddresses, listFavorites, listGroupons, openGroupon } from '@/api/shop'
import { useFanStore } from '@/store/fan'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '商品详情',
  },
})

const fanStore = useFanStore()
const detail = ref<IProductDetail | null>(null)
const productId = ref(0)
const selectedSkuId = ref(0)
const groupons = ref<IGroupon[]>([])
const favorited = ref(false)
const favoriteId = ref(0)

onLoad((options) => {
  const query = options as Record<string, string> | undefined
  if (query?.id) {
    productId.value = Number.parseInt(query.id)
    load()
  }
})

onShow(() => {
  if (productId.value === 0)
    return
  loadGroupons()
  loadFavorite()
})

function load() {
  getProductDetail(productId.value).then((res) => {
    detail.value = res
    if (res.skus.length > 0) {
      selectedSkuId.value = res.skus[0].id
    }
  }).catch(() => {
    detail.value = null
  })
}

const currentSku = computed<ISku | null>(() => {
  const d = detail.value
  if (!d)
    return null
  return d.skus.find(s => s.id === selectedSkuId.value) ?? null
})

const displayPrice = computed(() => {
  if (currentSku.value)
    return currentSku.value.price
  return detail.value?.product.price ?? 0
})

const displayStock = computed(() => {
  if (currentSku.value)
    return currentSku.value.stock
  return detail.value?.product.stock ?? 0
})

const displayOriginalPrice = computed(() => {
  const d = detail.value
  if (d && d.product.original_price > 0)
    return d.product.original_price
  return 0
})

/** 只有存在真实规格（非空 spec_json）时才显示规格选择器 */
const hasRealSkus = computed(() => {
  const d = detail.value
  if (!d)
    return false
  return d.skus.some(s => s.spec_json !== '' && s.spec_json !== '[]' && s.spec_json !== '{}')
})

const productImages = computed<string[]>(() => {
  const d = detail.value
  if (!d)
    return []
  const images = d.product.images
  if (images && images.length > 0 && images.charAt(0) === '[') {
    try {
      const arr = JSON.parse(images) as string[]
      if (arr.length > 0)
        return arr
    }
    catch {
      // 解析失败回退单图
    }
  }
  return d.product.image !== '' ? [d.product.image] : []
})

function ensureLogin(): boolean {
  if (!fanStore.hasLogin) {
    uni.navigateTo({ url: '/pages-sub/auth/login' })
    return false
  }
  return true
}

function onAddCart() {
  if (!ensureLogin())
    return
  const d = detail.value
  if (!d)
    return
  addCart(fanStore.openid, d.product.id, selectedSkuId.value, 1).then(() => {
    uni.showToast({ title: '已加入购物车', icon: 'success' })
  })
}

function onBuyNow() {
  if (!ensureLogin())
    return
  uni.navigateTo({
    url: `/pages-sub/shop/checkout?productId=${productId.value}&skuId=${selectedSkuId.value}&quantity=1`,
  })
}

function onSelectSku(skuId: number) {
  selectedSkuId.value = skuId
}

function loadGroupons() {
  if (!fanStore.hasLogin)
    return
  listGroupons().then((list) => {
    groupons.value = list.filter(g => g.product_id === productId.value)
  }).catch(() => {
    groupons.value = []
  })
}

function onOpenGroupon(groupon: IGroupon) {
  if (!ensureLogin())
    return
  listAddresses(fanStore.openid).then((addrs) => {
    if (addrs.length === 0) {
      uni.showToast({ title: '请先添加收货地址', icon: 'none' })
      return
    }
    const addr = addrs.find(a => a.is_default === 1) ?? addrs[0]
    openGroupon(groupon.id, fanStore.openid, addr.id, selectedSkuId.value).then(() => {
      uni.showToast({ title: '开团成功', icon: 'success' })
    })
  }).catch(() => {})
}

function loadFavorite() {
  if (!fanStore.hasLogin) {
    favorited.value = false
    favoriteId.value = 0
    return
  }
  listFavorites(fanStore.openid).then((list) => {
    const matched = list.find(f => f.product_id === productId.value)
    favorited.value = !!matched
    favoriteId.value = matched?.id ?? 0
  }).catch(() => {})
}

function onToggleFavorite() {
  if (!ensureLogin())
    return
  if (favorited.value) {
    deleteFavorite(favoriteId.value).then(() => {
      favorited.value = false
      uni.showToast({ title: '已取消收藏', icon: 'none' })
    })
  }
  else {
    addFavorite(fanStore.openid, productId.value).then(() => {
      favorited.value = true
      uni.showToast({ title: '已收藏', icon: 'success' })
    })
  }
}

const mySharePath = computed(() => {
  return productId.value > 0 ? `/pages-sub/shop/product-detail?id=${productId.value}` : ''
})

function onShare() {
  if (mySharePath.value !== '') {
    uni.showToast({ title: '点击右上角转发即可分享', icon: 'none' })
  }
}

function onService() {
  uni.showToast({ title: '客服功能待接入', icon: 'none' })
}

onShareAppMessage(() => {
  return {
    title: '精选好物，快来抢购',
    path: mySharePath.value,
  }
})
</script>

<template>
  <view class="page">
    <fg-navbar :title="$t('app.goodsDetail')" />
    <scroll-view scroll-y class="main">
      <view v-if="detail" class="content">
        <swiper
          v-if="productImages.length > 1"
          class="cover-swiper"
          circular
          indicator-dots
          indicator-color="rgba(255,255,255,0.5)"
          indicator-active-color="#ffffff"
        >
          <swiper-item v-for="(img, i) in productImages" :key="i">
            <image class="cover" :src="img" mode="aspectFill" />
          </swiper-item>
        </swiper>
        <image v-else class="cover" :src="productImages.length > 0 ? productImages[0] : detail.product.image" mode="aspectFill" />

        <fg-info-card
          :name="detail.product.name"
          :price="displayPrice"
          :original-price="displayOriginalPrice"
          :sales="detail.product.sales"
          :stock="displayStock"
          :favorited="favorited"
          @toggle-favorite="onToggleFavorite"
          @share="onShare"
        />

        <fg-groupon-section v-if="groupons.length > 0" :groupons="groupons" @open-groupon="onOpenGroupon" />

        <fg-sku-selector
          v-if="detail.skus.length > 0 && hasRealSkus"
          :skus="detail.skus"
          :selected-sku-id="selectedSkuId"
          @select="onSelectSku"
        />

        <view class="detail-content">
          <text class="content-title">{{ $t('app.goodsDetail') }}</text>
          <rich-text class="content-rich" :nodes="detail.product.content" />
        </view>

        <fg-comment-section :product-id="productId" />
      </view>
      <view v-else class="empty">
        <text class="empty-text">{{ $t('app.productNotFound') }}</text>
      </view>
    </scroll-view>

    <fg-bottom-bar
      :price="displayPrice"
      :original-price="displayOriginalPrice"
      @add-cart="onAddCart"
      @buy-now="onBuyNow"
      @service="onService"
    />
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
.content {
  display: flex;
  flex-direction: column;
}
.cover-swiper {
  width: 100%;
  height: 560rpx;
}
.cover {
  width: 100%;
  height: 560rpx;
  border-bottom-left-radius: 32rpx;
  border-bottom-right-radius: 32rpx;
}
.detail-content {
  margin: 20rpx 24rpx 0 24rpx;
  padding: 28rpx;
  background-color: #ffffff;
  border-radius: 24rpx;
  display: flex;
  flex-direction: column;
  box-shadow: var(--z-shadow);
}
.content-title {
  font-size: 15px;
  color: #1e293b;
  font-weight: 700;
}
.content-rich {
  margin-top: 16rpx;
  width: 100%;
}
.empty {
  padding: 80rpx;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
}
.empty-text {
  font-size: 14px;
  color: #94a3b8;
}
</style>
