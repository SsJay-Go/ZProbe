<script setup>
import { computed, onBeforeUnmount, ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { clearTrafficLogs, fetchTrafficLogs } from '../../api/system'

const props = defineProps({
  visible: {
    type: Boolean,
    default: false,
  },
})

const loading = ref(false)
const clearing = ref(false)
const entries = ref([])
const panelHeight = ref(288)
let timerId = null
let resizeSession = null

const hasEntries = computed(() => entries.value.length > 0)

async function loadLogs() {
  if (!props.visible || loading.value) return
  loading.value = true
  try {
    const response = await fetchTrafficLogs()
    entries.value = Array.isArray(response?.entries) ? response.entries : []
  } finally {
    loading.value = false
  }
}

async function clearLogs() {
  if (clearing.value) return
  clearing.value = true
  try {
    const response = await clearTrafficLogs()
    if (!response?.success) throw new Error(response?.message || 'Clear failed')
    entries.value = []
    ElMessage.success(response.message || '日志已清空')
  } catch (error) {
    ElMessage.error(error.message || '清空日志失败')
  } finally {
    clearing.value = false
  }
}

function startPolling() {
  stopPolling()
  void loadLogs()
  timerId = window.setInterval(() => {
    void loadLogs()
  }, 400)
}

function stopPolling() {
  if (timerId !== null) {
    window.clearInterval(timerId)
    timerId = null
  }
}

function beginResize(event) {
  resizeSession = {
    startY: event.clientY,
    startHeight: panelHeight.value,
  }
  document.body.style.userSelect = 'none'
  window.addEventListener('mousemove', handleResize)
  window.addEventListener('mouseup', endResize)
}

function handleResize(event) {
  if (!resizeSession) return

  const delta = resizeSession.startY - event.clientY
  const nextHeight = resizeSession.startHeight + delta
  const maxHeight = Math.max(220, Math.floor(window.innerHeight * 0.75))
  panelHeight.value = Math.min(maxHeight, Math.max(160, nextHeight))
}

function endResize() {
  resizeSession = null
  document.body.style.userSelect = ''
  window.removeEventListener('mousemove', handleResize)
  window.removeEventListener('mouseup', endResize)
}

function directionType(direction) {
  return direction === 'send' ? 'warning' : 'success'
}

watch(
  () => props.visible,
  (visible) => {
    if (visible) {
      startPolling()
      return
    }
    stopPolling()
  },
  { immediate: true }
)

onBeforeUnmount(() => {
  stopPolling()
  endResize()
})
</script>

<template>
  <section v-show="visible" class="border-t border-slate-200 bg-white/95" :style="{ height: `${panelHeight}px` }">
    <div
      class="flex h-4 cursor-row-resize items-center justify-center bg-slate-100 transition-colors hover:bg-slate-200"
      @mousedown="beginResize"
    >
      <div class="h-1 w-14 rounded-full bg-slate-400/80" />
    </div>
    <div class="flex items-center justify-between gap-3 px-4 py-3">
      <div>
        <div class="text-sm font-semibold text-slate-800">{{ $t('traffic.title') }}</div>
        <p class="mt-1 text-xs text-slate-500">{{ $t('traffic.description') }}</p>
      </div>
      <div class="flex items-center gap-2">
        <el-button size="small" plain :loading="loading" @click="loadLogs">
          {{ $t('traffic.refresh') }}
        </el-button>
        <el-button size="small" type="danger" plain :loading="clearing" @click="clearLogs">
          {{ $t('traffic.clear') }}
        </el-button>
      </div>
    </div>

    <div v-if="!hasEntries && !loading" class="px-4 pb-4 text-sm text-slate-500">
      {{ $t('traffic.empty') }}
    </div>

    <div v-else class="h-[calc(100%-76px)] overflow-auto px-4 pb-4">
      <div
        v-for="entry in entries"
        :key="entry.id"
        class="mb-3 rounded-2xl border border-slate-200 bg-slate-50 p-3 shadow-sm last:mb-0"
      >
        <div class="mb-2 flex items-center gap-2 text-xs text-slate-500">
          <span class="font-medium text-slate-700">#{{ entry.id }}</span>
          <el-tag size="small" effect="light" :type="directionType(entry.direction)">
            {{ entry.direction === 'send' ? $t('traffic.send') : $t('traffic.recv') }}
          </el-tag>
          <span>{{ entry.category }}</span>
        </div>
        <pre class="overflow-x-auto rounded-xl border border-slate-200 bg-white px-3 py-2 text-xs leading-5 text-slate-700">{{ entry.message }}</pre>
      </div>
    </div>
  </section>
</template>
