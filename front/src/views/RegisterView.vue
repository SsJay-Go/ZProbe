<script setup>
import { ref, reactive, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { Plus, Delete, VideoPlay, VideoPause, Refresh, Setting } from '@element-plus/icons-vue'

const { t } = useI18n()

// ========== 读取定义窗口 ==========
const readWindows = ref([createDefaultWindow(1)])
const activeWindowId = ref(1)
let windowIdCounter = 1

function createDefaultWindow(id) {
  return {
    id,
    name: `${t('register.window')} ${id}`,
    slaveId: 1,
    functionCode: '03',
    startAddress: 0,
    quantity: 10,
    scanRate: 1000,
    polling: false,
    displayFormat: 'decimal',
    columns: 10,
    registers: Array.from({ length: 10 }, (_, i) => ({
      address: i,
      value: 0,
      prevValue: null,
      changed: false,
      alias: '',
      desc: '',
    })),
  }
}

function addWindow() {
  windowIdCounter++
  const win = createDefaultWindow(windowIdCounter)
  readWindows.value.push(win)
  activeWindowId.value = win.id
}

function removeWindow(id) {
  const idx = readWindows.value.findIndex(w => w.id === id)
  if (idx === -1 || readWindows.value.length <= 1) return
  readWindows.value.splice(idx, 1)
  if (activeWindowId.value === id) {
    activeWindowId.value = readWindows.value[0].id
  }
}

const activeWindow = computed(() =>
  readWindows.value.find(w => w.id === activeWindowId.value) || readWindows.value[0]
)

// ========== 功能码选项 ==========
const functionCodes = computed(() => [
  { value: '01', label: t('register.fc01') },
  { value: '02', label: t('register.fc02') },
  { value: '03', label: t('register.fc03') },
  { value: '04', label: t('register.fc04') },
])

// ========== 显示格式 ==========
const displayFormats = computed(() => [
  { value: 'decimal', label: t('register.decimal') },
  { value: 'unsigned', label: t('register.unsigned') },
  { value: 'hex', label: t('register.hex') },
  { value: 'binary', label: t('register.binary') },
  { value: 'float', label: t('register.float') },
  { value: 'ascii', label: t('register.ascii') },
])

// ========== 数据格式化 ==========
function formatValue(value, format) {
  if (value === null || value === undefined) return '-'
  const v = Number(value)
  switch (format) {
    case 'decimal': {
      // Signed 16-bit
      const signed = v > 32767 ? v - 65536 : v
      return signed.toString()
    }
    case 'unsigned':
      return (v & 0xFFFF).toString()
    case 'hex':
      return '0x' + (v & 0xFFFF).toString(16).toUpperCase().padStart(4, '0')
    case 'binary':
      return (v & 0xFFFF).toString(2).padStart(16, '0')
    case 'float':
      return v.toFixed(2)
    case 'ascii': {
      const hi = (v >> 8) & 0xFF
      const lo = v & 0xFF
      const ch = (hi >= 32 && hi <= 126 ? String.fromCharCode(hi) : '.') +
                 (lo >= 32 && lo <= 126 ? String.fromCharCode(lo) : '.')
      return ch
    }
    default:
      return v.toString()
  }
}

// ========== 参数变更时刷新寄存器列表 ==========
function applySettings() {
  const win = activeWindow.value
  win.registers = Array.from({ length: win.quantity }, (_, i) => ({
    address: win.startAddress + i,
    value: 0,
    prevValue: null,
    changed: false,
    alias: '',
    desc: '',
  }))
}

// ========== 轮询控制 ==========
const pollingTimers = new Map()

function togglePolling(win) {
  win.polling = !win.polling
  if (win.polling) {
    // 模拟数据 - 实际使用时替换为真实请求
    const timer = setInterval(() => {
      win.registers.forEach(reg => {
        reg.prevValue = reg.value
        // 模拟：随机变化
        reg.value = Math.floor(Math.random() * 65536)
        reg.changed = reg.value !== reg.prevValue
      })
    }, win.scanRate)
    pollingTimers.set(win.id, timer)
  } else {
    clearInterval(pollingTimers.get(win.id))
    pollingTimers.delete(win.id)
  }
}

// ========== 单次读取 ==========
function readOnce() {
  const win = activeWindow.value
  win.registers.forEach(reg => {
    reg.prevValue = reg.value
    reg.value = Math.floor(Math.random() * 65536)
    reg.changed = reg.value !== reg.prevValue
  })
}

// ========== 写入寄存器（双击编辑） ==========
const editingCell = ref(null)
const editValue = ref('')

// ========== 列数选项和多列布局 ==========
const columnOptions = [1, 2, 5, 10, 15, 20, 25, 30]

const isDetailMode = computed(() => activeWindow.value.columns <= 5)

const registerRows = computed(() => {
  const win = activeWindow.value
  const cols = win.columns
  const regs = win.registers
  const rows = []
  for (let i = 0; i < regs.length; i += cols) {
    const cells = []
    for (let j = 0; j < cols; j++) {
      cells.push(i + j < regs.length ? regs[i + j] : null)
    }
    rows.push({
      baseAddress: regs[i].address,
      cells,
    })
  }
  return rows
})

function startEdit(reg) {
  editingCell.value = reg.address
  editValue.value = reg.value.toString()
}

function confirmEdit(reg) {
  const v = parseInt(editValue.value, 10)
  if (!isNaN(v)) {
    reg.prevValue = reg.value
    reg.value = v & 0xFFFF
    reg.changed = true
  }
  editingCell.value = null
}
</script>

<template>
  <div class="h-full flex flex-col">
    <!-- 窗口标签栏 -->
    <div class="flex items-center gap-1 bg-gray-100 px-2 py-1 border-b border-gray-200 shrink-0">
      <button
        v-for="win in readWindows"
        :key="win.id"
        @click="activeWindowId = win.id"
        class="group flex items-center gap-1 px-3 py-1 rounded text-xs cursor-pointer border-none transition-colors"
        :class="activeWindowId === win.id
          ? 'bg-white text-blue-600 shadow-xs font-medium'
          : 'bg-transparent text-gray-500 hover:bg-gray-50'"
      >
        <span
          class="w-1.5 h-1.5 rounded-full shrink-0"
          :class="win.polling ? 'bg-green-500' : 'bg-gray-300'"
        />
        {{ win.name }}
        <span
          v-if="readWindows.length > 1"
          @click.stop="removeWindow(win.id)"
          class="ml-1 opacity-0 group-hover:opacity-100 text-gray-400 hover:text-red-500 transition-opacity"
        >×</span>
      </button>
      <button
        @click="addWindow"
        class="flex items-center justify-center w-6 h-6 rounded text-gray-400 hover:bg-gray-200 hover:text-gray-600 cursor-pointer border-none bg-transparent transition-colors"
      >
        <el-icon :size="14"><Plus /></el-icon>
      </button>
    </div>

    <!-- 工具条：连接参数 + 操作 -->
    <div class="flex items-center gap-3 px-3 py-2 bg-white border-b border-gray-200 shrink-0 flex-wrap">
      <div class="flex items-center gap-1.5">
        <span class="text-xs text-gray-500">{{ $t('register.slaveId') }}</span>
        <el-input-number
          v-model="activeWindow.slaveId"
          :min="1" :max="247"
          size="small"
          controls-position="right"
          class="w-20!"
        />
      </div>

      <div class="flex items-center gap-1.5">
        <span class="text-xs text-gray-500">{{ $t('register.functionCode') }}</span>
        <el-select v-model="activeWindow.functionCode" size="small" class="w-40!">
          <el-option
            v-for="fc in functionCodes"
            :key="fc.value"
            :label="fc.label"
            :value="fc.value"
          />
        </el-select>
      </div>

      <div class="flex items-center gap-1.5">
        <span class="text-xs text-gray-500">{{ $t('register.startAddress') }}</span>
        <el-input-number
          v-model="activeWindow.startAddress"
          :min="0" :max="65535"
          size="small"
          controls-position="right"
          class="w-24!"
        />
      </div>

      <div class="flex items-center gap-1.5">
        <span class="text-xs text-gray-500">{{ $t('register.quantity') }}</span>
        <el-input-number
          v-model="activeWindow.quantity"
          :min="1" :max="125"
          size="small"
          controls-position="right"
          class="w-20!"
        />
      </div>

      <div class="flex items-center gap-1.5">
        <span class="text-xs text-gray-500">{{ $t('register.scanRate') }}</span>
        <el-input-number
          v-model="activeWindow.scanRate"
          :min="50" :max="60000" :step="100"
          size="small"
          controls-position="right"
          class="w-24!"
        />
      </div>

      <div class="flex items-center gap-1.5">
        <span class="text-xs text-gray-500">{{ $t('register.columns') }}</span>
        <el-select v-model="activeWindow.columns" size="small" class="w-20!">
          <el-option v-for="n in columnOptions" :key="n" :label="n" :value="n" />
        </el-select>
      </div>

      <div class="flex items-center gap-1.5">
        <span class="text-xs text-gray-500">{{ $t('register.displayFormat') }}</span>
        <el-select v-model="activeWindow.displayFormat" size="small" class="w-36!">
          <el-option
            v-for="fmt in displayFormats"
            :key="fmt.value"
            :label="fmt.label"
            :value="fmt.value"
          />
        </el-select>
      </div>

      <div class="flex items-center gap-1.5 ml-auto">
        <el-button size="small" @click="applySettings" :icon="Setting">{{ $t('register.apply') }}</el-button>
        <el-button size="small" @click="readOnce" :icon="Refresh">{{ $t('register.readOnce') }}</el-button>
        <el-button
          size="small"
          :type="activeWindow.polling ? 'danger' : 'primary'"
          @click="togglePolling(activeWindow)"
          :icon="activeWindow.polling ? VideoPause : VideoPlay"
        >
          {{ activeWindow.polling ? $t('register.stop') : $t('register.poll') }}
        </el-button>
      </div>
    </div>

    <!-- 寄存器表格（多列网格） -->
    <div class="flex-1 overflow-auto">
      <!-- 详细模式：<=10列，每列都有别名/值/描述 -->
      <table v-if="isDetailMode" class="border-collapse text-xs">
        <thead class="sticky top-0 z-10">
          <tr class="bg-gray-50 text-gray-500">
            <th class="px-2 py-1.5 text-center font-medium border-b border-r border-gray-200 w-14">{{ $t('register.address') }}</th>
            <template v-for="col in activeWindow.columns" :key="col">
              <th class="px-2 py-1.5 text-left font-medium border-b border-r border-gray-200 w-24">{{ $t('register.alias') }}</th>
              <th class="px-2 py-1.5 text-center font-medium border-b border-r border-gray-200 w-24">
                {{ $t('register.value') }}{{ activeWindow.columns > 1 ? ` (+${col - 1})` : '' }}
              </th>
              <th class="px-2 py-1.5 text-left font-medium border-b border-r border-gray-200 w-28">{{ $t('register.description') }}</th>
            </template>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="(row, rowIdx) in registerRows"
            :key="rowIdx"
            class="hover:bg-blue-50/30"
          >
            <td class="px-2 py-1 border-b border-r border-gray-200 bg-gray-50 text-gray-500 font-mono text-center font-medium">
              {{ row.baseAddress.toString().padStart(5, '0') }}
            </td>
            <template v-for="(reg, cIdx) in row.cells" :key="reg ? reg.address : `e${cIdx}`">
              <!-- 别名 -->
              <td class="px-2 py-1 border-b border-r border-gray-100 text-xs">
                <input
                  v-if="reg"
                  v-model="reg.alias"
                  class="w-full bg-transparent border-none outline-none text-xs text-gray-600 placeholder-gray-300"
                  placeholder="别名"
                />
              </td>
              <!-- 值 -->
              <td
                class="px-2 py-1 border-b border-r border-gray-100 text-center font-mono cursor-pointer select-none transition-colors"
                :class="[
                  reg?.changed ? 'bg-yellow-50 text-red-600 font-semibold' : 'text-gray-800',
                  reg ? 'hover:bg-blue-50' : 'bg-gray-50/50'
                ]"
                @dblclick="reg && startEdit(reg)"
              >
                <template v-if="reg && editingCell === reg.address">
                  <el-input v-model="editValue" size="small" class="w-full!" autofocus @keyup.enter="confirmEdit(reg)" @blur="confirmEdit(reg)" />
                </template>
                <template v-else-if="reg">
                  {{ formatValue(reg.value, activeWindow.displayFormat) }}
                </template>
              </td>
              <!-- 描述 -->
              <td class="px-2 py-1 border-b border-r border-gray-100 text-xs">
                <input
                  v-if="reg"
                  v-model="reg.desc"
                  class="w-full bg-transparent border-none outline-none text-xs text-gray-500 placeholder-gray-300"
                  placeholder="描述"
                />
              </td>
            </template>
          </tr>
        </tbody>
      </table>

      <!-- 紧凑模式：>10列纯网格 -->
      <table v-else class="border-collapse text-xs">
        <thead class="sticky top-0 z-10">
          <tr class="bg-gray-50 text-gray-500">
            <th class="px-2 py-1.5 text-center font-medium border-b border-r border-gray-200 w-16"></th>
            <th
              v-for="col in activeWindow.columns"
              :key="col"
              class="px-2 py-1.5 text-center font-medium border-b border-r border-gray-200 w-20"
            >
              +{{ col - 1 }}
            </th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="(row, rowIdx) in registerRows"
            :key="rowIdx"
            class="hover:bg-blue-50/30"
          >
            <td class="px-2 py-1 border-b border-r border-gray-200 bg-gray-50 text-gray-500 font-mono text-center font-medium">
              {{ row.baseAddress.toString().padStart(5, '0') }}
            </td>
            <td
              v-for="(reg, cIdx) in row.cells"
              :key="reg ? reg.address : `e${cIdx}`"
              class="px-2 py-1 border-b border-r border-gray-100 text-center font-mono cursor-pointer select-none transition-colors"
              :class="[
                reg?.changed ? 'bg-yellow-50 text-red-600 font-semibold' : 'text-gray-800',
                reg ? 'hover:bg-blue-50' : 'bg-gray-50/50'
              ]"
              :title="reg ? `${reg.address} ${reg.alias || ''}` : ''"
              @dblclick="reg && startEdit(reg)"
            >
              <template v-if="reg && editingCell === reg.address">
                <el-input v-model="editValue" size="small" class="w-full!" autofocus @keyup.enter="confirmEdit(reg)" @blur="confirmEdit(reg)" />
              </template>
              <template v-else-if="reg">
                {{ formatValue(reg.value, activeWindow.displayFormat) }}
              </template>
            </td>
          </tr>
        </tbody>
      </table>
    </div>

    <!-- 底部状态栏 -->
    <div class="flex items-center justify-between px-3 py-1 bg-gray-50 border-t border-gray-200 text-[11px] text-gray-400 shrink-0">
      <div class="flex items-center gap-4">
        <span>Slave: {{ activeWindow.slaveId }}</span>
        <span>FC: {{ activeWindow.functionCode }}</span>
        <span>{{ $t('register.address') }}: {{ activeWindow.startAddress }}–{{ activeWindow.startAddress + activeWindow.quantity - 1 }}</span>
        <span>{{ $t('register.quantity') }}: {{ activeWindow.quantity }}</span>
      </div>
      <div class="flex items-center gap-4">
        <span v-if="activeWindow.polling" class="text-green-600">
          ● {{ $t('register.pollingStatus') }} ({{ activeWindow.scanRate }}ms)
        </span>
        <span v-else class="text-gray-400">○ {{ $t('register.idle') }}</span>
        <span>{{ $t('register.format') }}: {{ displayFormats.find(f => f.value === activeWindow.displayFormat)?.label }}</span>
      </div>
    </div>
  </div>
</template>
