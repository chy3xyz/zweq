<script setup lang="ts">
import { onMounted, ref } from 'vue'
import type { IComment } from '@/api/shop'
import { createComment, listComments } from '@/api/shop'
import { t } from '@/i18n'
import { useFanStore } from '@/store/fan'
import { formatTime } from '@/utils/format'

const props = defineProps<{
  productId: number
}>()

const fanStore = useFanStore()
const comments = ref<IComment[]>([])
const commentText = ref('')

function load() {
  if (!fanStore.hasLogin) {
    comments.value = []
    return
  }
  listComments(props.productId).then((list) => {
    comments.value = list
  })
}

function onComment() {
  if (!fanStore.hasLogin) {
    uni.navigateTo({ url: '/pages-sub/auth/login' })
    return
  }
  if (commentText.value === '') {
    uni.showToast({ title: '请输入评论内容', icon: 'none' })
    return
  }
  createComment(props.productId, fanStore.openid, 5, commentText.value).then(() => {
    uni.showToast({ title: '评论成功', icon: 'success' })
    commentText.value = ''
    load()
  })
}

onMounted(() => {
  load()
})
</script>

<template>
  <view class="comment-wrap">
    <text class="comment-title">{{ $t('app.comment') }}</text>
    <view class="comment-input-row">
      <input v-model="commentText" class="comment-input" :placeholder="t('app.commentPlaceholder')">
      <view class="comment-btn" @click="onComment">
        <text class="comment-btn-text">{{ $t('app.published') }}</text>
      </view>
    </view>
    <view v-if="comments.length === 0" class="comment-empty">
      <text class="comment-empty-text">{{ $t('app.noComment') }}</text>
    </view>
    <view v-for="c in comments" :key="c.id" class="comment-item">
      <view class="comment-head">
        <text class="comment-star">{{ c.star }} 星</text>
        <text class="comment-time">{{ formatTime(c.created_at) }}</text>
      </view>
      <text class="comment-content">{{ c.content }}</text>
    </view>
  </view>
</template>

<style scoped lang="scss">
.comment-wrap {
  margin-top: 16rpx;
  padding: 24rpx;
  padding-bottom: 140rpx;
  background-color: #ffffff;
  display: flex;
  flex-direction: column;
}
.comment-title {
  font-size: 15px;
  color: #1e293b;
  font-weight: 700;
}
.comment-input-row {
  margin-top: 16rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
}
.comment-input {
  flex: 1;
  height: 72rpx;
  padding: 0 20rpx;
  border-width: 1px;
  border-color: #e2e8f0;
  border-style: solid;
  border-radius: 8px;
  font-size: 13px;
  color: #334155;
  background-color: #f8fafc;
}
.comment-btn {
  margin-left: 16rpx;
  padding: 0 32rpx;
  height: 72rpx;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  border-radius: 8px;
  background-color: var(--theme-color, #0957de);
}
.comment-btn-text {
  font-size: 14px;
  color: #ffffff;
  font-weight: 700;
}
.comment-empty {
  margin-top: 24rpx;
}
.comment-empty-text {
  font-size: 13px;
  color: #94a3b8;
}
.comment-item {
  margin-top: 24rpx;
  padding-top: 20rpx;
  border-top-width: 1px;
  border-top-color: #f1f5f9;
  border-top-style: solid;
  display: flex;
  flex-direction: column;
}
.comment-head {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
}
.comment-star {
  font-size: 13px;
  color: #f59e0b;
}
.comment-time {
  font-size: 12px;
  color: #94a3b8;
}
.comment-content {
  margin-top: 12rpx;
  font-size: 13px;
  color: #475569;
  line-height: 20px;
}
</style>
