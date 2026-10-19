<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { chatWithAi } from '@/api/ai'
import { safeAreaInsets } from '@/utils/systemInfo'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: 'AI 智能助手',
  },
})

interface ChatMessage {
  id: string
  sender: string
  content: string
  time: string
}

const messages = ref<ChatMessage[]>([])
const inputText = ref('')
const isTyping = ref(false)
const isSending = ref(false)
const scrollTop = ref(0)

const suggestions = ['我的订单怎么看？', '今天怎么签到？', '有哪些优惠券？']

function isAiMessage(sender: string): boolean {
  return sender === 'ai'
}

const safeAreaBottom = computed(() => safeAreaInsets.value?.bottom ?? 0)

function getCurrentTime(): string {
  const date = new Date()
  const hours = date.getHours()
  const minutes = date.getMinutes()
  const hStr = hours < 10 ? `0${hours}` : `${hours}`
  const mStr = minutes < 10 ? `0${minutes}` : `${minutes}`
  return `${hStr}:${mStr}`
}

function scrollToBottom() {
  setTimeout(() => {
    scrollTop.value += 1000
  }, 100)
}

function pushAi(content: string) {
  messages.value.push({
    id: `${Date.now()}_ai`,
    sender: 'ai',
    content,
    time: getCurrentTime(),
  })
}

function errorMessage(err: unknown): string {
  if (err && typeof err === 'object' && 'message' in err) {
    const message = (err as { message?: unknown }).message
    if (typeof message === 'string' && message !== '')
      return message
  }
  return '请稍后再试'
}

async function sendMessage() {
  const content = inputText.value.trim()
  if (content === '' || isSending.value)
    return

  messages.value.push({
    id: `${Date.now()}_user`,
    sender: 'user',
    content,
    time: getCurrentTime(),
  })

  inputText.value = ''
  isTyping.value = true
  isSending.value = true
  scrollToBottom()

  try {
    const res = await chatWithAi(content)
    pushAi(res.answer?.trim() ? res.answer.trim() : 'AI 没有返回内容')
  }
  catch (err) {
    pushAi(`AI 服务暂不可用：${errorMessage(err)}`)
  }
  finally {
    isTyping.value = false
    isSending.value = false
    scrollToBottom()
  }
}

function sendSuggestion(text: string) {
  inputText.value = text
  sendMessage()
}

onMounted(() => {
  pushAi('你好！我是 ZWEQ 的 AI 智能助手，已接入 zigmodu AI 引擎。可以问我商品、订单、签到、优惠券等问题。✨')
})
</script>

<template>
  <view class="page-root">
    <fg-navbar title="AI 智能助手" :show-back="true" />

    <view class="ai-hint">
      <view class="ai-hint-dot" />
      <text class="ai-hint-text">由 zigmodu AI 引擎驱动 · 回答仅供参考</text>
    </view>

    <scroll-view
      class="chat-list"
      scroll-y
      :scroll-top="scrollTop"
      :scroll-with-animation="true"
    >
      <view v-for="msg in messages" :key="msg.id" class="msg-item">
        <view v-if="isAiMessage(msg.sender)" class="msg-row-start">
          <view class="avatar-ai">
            <text class="avatar-text">AI</text>
          </view>
          <view class="msg-content-left">
            <view class="bubble-ai">
              <text class="bubble-text">{{ msg.content }}</text>
            </view>
            <text class="msg-time">{{ msg.time }}</text>
          </view>
        </view>

        <view v-else class="msg-row-end">
          <view class="msg-content-right">
            <view class="bubble-user">
              <text class="bubble-text-user">{{ msg.content }}</text>
            </view>
            <text class="msg-time">{{ msg.time }}</text>
          </view>
          <view class="avatar-me">
            <text class="avatar-me-text">ME</text>
          </view>
        </view>
      </view>

      <view v-if="isTyping" class="msg-row-start">
        <view class="avatar-ai">
          <text class="avatar-text">AI</text>
        </view>
        <view class="bubble-ai">
          <text class="typing-text">AI 正在思考中...</text>
        </view>
      </view>

      <view :style="{ height: `${safeAreaBottom + 70}px` }" />
    </scroll-view>

    <view class="footer-fixed app-fixed-bar" :style="{ paddingBottom: `${safeAreaBottom + 10}px` }">
      <scroll-view scroll-x class="suggestions">
        <view class="suggestion-row">
          <view v-for="s in suggestions" :key="s" class="suggestion" @click="sendSuggestion(s)">
            {{ s }}
          </view>
        </view>
      </scroll-view>

      <view class="input-row">
        <input
          v-model="inputText"
          type="text"
          placeholder="和 AI 助手聊点什么吧..."
          placeholder-style="color: #94a3b8"
          class="chat-input"
          confirm-type="send"
          @confirm="sendMessage"
        >
        <view class="send-btn" :class="{ 'send-disabled': isSending }" @click="sendMessage">
          <text class="send-icon">{{ isSending ? '…' : '➤' }}</text>
        </view>
      </view>
    </view>
  </view>
</template>

<style scoped lang="scss">
.page-root {
  height: 100vh;
  display: flex;
  flex-direction: column;
  background-color: var(--z-bg, #f5f7fb);
}
.ai-hint {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  padding: 14rpx 24rpx;
  background-color: #eef4ff;
}
.ai-hint-dot {
  width: 10rpx;
  height: 10rpx;
  border-radius: 5rpx;
  background-color: #10b981;
  margin-right: 10rpx;
}
.ai-hint-text {
  font-size: 22rpx;
  color: #64748b;
}
.chat-list {
  flex: 1;
  padding: 20rpx 30rpx;
  box-sizing: border-box;
}
.msg-item {
  margin-bottom: 30rpx;
  display: flex;
  flex-direction: column;
}
.msg-row-start {
  display: flex;
  flex-direction: row;
  align-items: flex-start;
}
.msg-row-end {
  display: flex;
  flex-direction: row;
  align-items: flex-start;
  justify-content: flex-end;
}
.avatar-ai {
  width: 72rpx;
  height: 72rpx;
  border-radius: 36rpx;
  background-color: var(--theme-color, #0957de);
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  margin-right: 20rpx;
}
.avatar-text {
  color: #ffffff;
  font-size: 24rpx;
  font-weight: 700;
}
.avatar-me {
  width: 72rpx;
  height: 72rpx;
  border-radius: 36rpx;
  background-color: #e2e8f0;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  margin-left: 20rpx;
}
.avatar-me-text {
  color: #64748b;
  font-size: 24rpx;
  font-weight: 700;
}
.msg-content-left {
  display: flex;
  flex-direction: column;
  max-width: 70%;
}
.msg-content-right {
  display: flex;
  flex-direction: column;
  align-items: flex-end;
  max-width: 70%;
}
.bubble-ai {
  background-color: #ffffff;
  padding: 24rpx;
  border-radius: 0 32rpx 32rpx 32rpx;
  box-shadow: 0 4rpx 12rpx rgba(15, 23, 42, 0.06);
}
.bubble-user {
  background-color: #10b981;
  padding: 24rpx;
  border-radius: 32rpx 0 32rpx 32rpx;
  box-shadow: 0 4rpx 12rpx rgba(15, 23, 42, 0.06);
}
.bubble-text {
  color: #1e293b;
  font-size: 28rpx;
  line-height: 1.6;
}
.bubble-text-user {
  color: #ffffff;
  font-size: 28rpx;
  line-height: 1.6;
}
.typing-text {
  color: #64748b;
  font-size: 28rpx;
}
.msg-time {
  color: #94a3b8;
  font-size: 20rpx;
  margin-top: 8rpx;
  margin-left: 8rpx;
}
.footer-fixed {
  position: fixed;
  left: 0;
  right: 0;
  bottom: 0;
  z-index: 100;
  background-color: #ffffff;
  border-top: 1px solid #e2e8f0;
  border-radius: 28rpx 28rpx 0 0;
  box-shadow: 0 -10rpx 30rpx rgba(15, 23, 42, 0.06);
  padding: 20rpx;
}
.suggestions {
  width: 100%;
  white-space: nowrap;
  margin-bottom: 14rpx;
}
.suggestion-row {
  display: flex;
  flex-direction: row;
  align-items: center;
}
.suggestion {
  flex-shrink: 0;
  margin-right: 14rpx;
  padding: 10rpx 22rpx;
  border-radius: 24rpx;
  background-color: #f1f5f9;
  font-size: 22rpx;
  color: #475569;
}
.send-disabled {
  opacity: 0.6;
}
.input-row {
  display: flex;
  flex-direction: row;
  align-items: center;
  background-color: #f1f5f9;
  border-radius: 48rpx;
  padding: 12rpx 24rpx;
}
.chat-input {
  flex: 1;
  height: 72rpx;
  background-color: #f1f5f9;
  color: #1e293b;
  font-size: 28rpx;
}
.send-btn {
  width: 64rpx;
  height: 64rpx;
  border-radius: 32rpx;
  background-color: var(--theme-color, #0957de);
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  margin-left: 16rpx;
}
.send-icon {
  color: #ffffff;
  font-size: 28rpx;
}
</style>
