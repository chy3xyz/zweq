<script setup lang="ts">
import { ref } from 'vue'
import { onShow } from '@dcloudio/uni-app'
import type { IVote, IVoteDetail } from '@/api/scene'
import { getVoteDetail, listVotes, voteBallot } from '@/api/scene'
import { t } from '@/i18n'
import { useFanStore } from '@/store/fan'

definePage({
  style: {
    navigationStyle: 'custom',
    navigationBarTitleText: '投票',
  },
})

const fanStore = useFanStore()
const votes = ref<IVote[]>([])
const detail = ref<IVoteDetail | null>(null)
const options = ref<string[]>([])
const tally = ref<number[]>([])
const activeId = ref(-1)

function load() {
  listVotes(1, 20).then((res) => {
    votes.value = res.list
  })
}

function onPick(vote: IVote) {
  activeId.value = vote.id
  getVoteDetail(vote.id).then((d) => {
    detail.value = d
    options.value = JSON.parse(d.options_json) as string[]
    tally.value = d.tally
  })
}

function onVote(optionIndex: number) {
  if (!detail.value)
    return
  const voteId = detail.value.id
  voteBallot(voteId, optionIndex).then(() => {
    uni.showToast({ title: t('mkt.voteSuccess'), icon: 'success' })
    getVoteDetail(voteId).then((d) => {
      detail.value = d
      options.value = JSON.parse(d.options_json) as string[]
      tally.value = d.tally
    })
  })
}

onShow(() => {
  if (!fanStore.hasLogin) {
    uni.navigateTo({ url: '/pages-sub/auth/login' })
    return
  }
  load()
})
</script>

<template>
  <view class="z-page">
    <fg-navbar :title="$t('mkt.vote')" />
    <scroll-view scroll-y class="z-body">
      <view v-for="v in votes" :key="v.id" class="mx-4 mt-2 flex flex-col rounded-3 bg-white">
        <view class="p-6" @click="onPick(v)">
          <text class="text-[15px] text-[#1e293b] font-bold">{{ v.title }}</text>
        </view>
        <view v-if="detail && activeId === v.id" class="flex flex-col px-6 pb-6">
          <view v-for="(opt, idx) in options" :key="idx" class="mt-3 flex flex-row items-center justify-between rounded-2 bg-[#f8fafc] p-5" @click="onVote(idx)">
            <text class="text-[14px] text-[#1e293b]">{{ opt }}</text>
            <text class="text-[13px] text-[#ef4444]">{{ $t('mkt.voteCount', { count: tally[idx] }) }}</text>
          </view>
        </view>
      </view>
      <fg-empty-view v-if="votes.length === 0" :text="$t('mkt.noVotes')" />
    </scroll-view>
  </view>
</template>
