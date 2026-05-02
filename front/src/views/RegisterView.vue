<script setup>
import { ref, computed, watch, onBeforeUnmount } from 'vue'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import { Plus, VideoPlay, VideoPause, Refresh, Setting } from '@element-plus/icons-vue'
import { readRegisters } from '../api/modbus'

const { t } = useI18n()

const props = defineProps({
  connected: {
    type: Boolean,
    default: false,
  },
  connectionId: {
    type: String,
    default: '',
  },
  transport: {
    type: String,
    default: '',
  },
  slaveId: {
    type: Number,
    default: 1,
  },
})

function createRegisters(startAddress, quantity, previous = []) {
  return Array.from({ length: quantity }, (_, index) => {
    const previousRegister = previous[index]
    return {
      address: startAddress + index,
      value: previousRegister?.value ?? 0,
      prevValue: previousRegister?.prevValue ?? null,
      changed: false,
      alias: previousRegister?.alias ?? '',
      desc: previousRegister?.desc ?? '',
    }
  })
}

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
    loading: false,
    lastError: '',
    lastReadAt: '',
    displayFormat: 'decimal',
    columns: 10,
    registers: createRegisters(0, 10),
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
  stopPolling(readWindows.value[idx])
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
  { value: '01', label: t('register.fc01'), disabled: true, target: null },
  { value: '02', label: t('register.fc02'), disabled: true, target: null },
  { value: '03', label: t('register.fc03'), disabled: false, target: 'holding_registers' },
  { value: '04', label: t('register.fc04'), disabled: false, target: 'input_registers' },
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
  win.registers = createRegisters(win.startAddress, win.quantity, win.registers)
}

// ========== 轮询控制 ==========
const pollingTimers = new Map()

const canEditSlaveId = computed(() => props.transport === 'rtu')
const canRead = computed(() => props.connected && props.connectionId.length > 0)
const currentSlaveId = computed(() => (canEditSlaveId.value ? activeWindow.value.slaveId : props.slaveId || 1))

function stopPolling(win) {
  const timer = pollingTimers.get(win.id)
  if (timer) {
    clearInterval(timer)
    pollingTimers.delete(win.id)
  }
  win.polling = false
}

function stopAllPolling() {
  readWindows.value.forEach(stopPolling)
}

function applyReadResult(win, values) {
  win.registers = Array.from({ length: win.quantity }, (_, index) => {
    const existing = win.registers[index]
    const nextValue = values[index] ?? 0

    return {
      address: win.startAddress + index,
      value: nextValue,
      prevValue: existing?.value ?? null,
      changed: nextValue !== (existing?.value ?? null),
      alias: existing?.alias ?? '',
      desc: existing?.desc ?? '',
    }
  })
}

async function readWindow(win, options = {}) {
  if (!canRead.value) {
    if (!options.silent) {
      ElMessage.warning(t('register.connectFirst'))
    }
    stopPolling(win)
    return false
  }

  const target = functionCodes.value.find(({ value }) => value === win.functionCode)?.target ?? null
  if (!target) {
    if (!options.silent) {
      ElMessage.warning(t('register.unsupportedFunction'))
    }
    stopPolling(win)
    return false
  }

  if (win.loading) {
    return false
  }

  win.loading = true

  try {
    const response = await readRegisters({
      connectionId: props.connectionId,
      target,
      startAddress: win.startAddress,
      quantity: win.quantity,
      slaveId: canEditSlaveId.value ? win.slaveId : null,
    })

    if (!response?.success || !Array.isArray(response.registers)) {
      const message = response?.message || t('register.readFailed')
      if (!options.silent) {
        ElMessage.error(message)
      }
      throw new Error(message)
    }

    applyReadResult(win, response.registers)
    win.lastError = ''
    win.lastReadAt = new Date().toLocaleTimeString()
    return true
  } catch (error) {
    win.lastError = error?.response?.data?.message || error?.message || t('register.readFailed')
    if (options.stopPollingOnError !== false) {
      stopPolling(win)
    }
    return false
  } finally {
    win.loading = false
  }
}

async function togglePolling(win) {
  if (win.polling) {
    stopPolling(win)
    return
  }

  const initialReadSucceeded = await readWindow(win)
  if (!initialReadSucceeded) {
    return
  }

  win.polling = true
  const timer = setInterval(() => {
    void readWindow(win, { silent: true })
  }, win.scanRate)
  pollingTimers.set(win.id, timer)
}

// ========== 单次读取 ==========
async function readOnce() {
  await readWindow(activeWindow.value)
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

const detailHeaders = computed(() => {
  const headers = []

  for (let columnIndex = 0; columnIndex < activeWindow.value.columns; columnIndex += 1) {
    headers.push(
      {
        key: `alias-${columnIndex}`,
        type: 'alias',
        label: t('register.alias'),
      },
      {
        key: `value-${columnIndex}`,
        type: 'value',
        label: `${t('register.value')}${activeWindow.value.columns > 1 ? ` (+${columnIndex})` : ''}`,
      },
      {
        key: `desc-${columnIndex}`,
        type: 'desc',
        label: t('register.description'),
      }
    )
  }

  return headers
})

function detailCells(row) {
  return row.cells.flatMap((reg, index) => ([
    {
      key: reg ? `alias-${reg.address}` : `alias-empty-${index}`,
      type: 'alias',
      reg,
    },
    {
      key: reg ? `value-${reg.address}` : `value-empty-${index}`,
      type: 'value',
      reg,
    },
    {
      key: reg ? `desc-${reg.address}` : `desc-empty-${index}`,
      type: 'desc',
      reg,
    },
  ]))
}

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

watch(
  () => [props.transport, props.slaveId],
  () => {
    if (props.transport !== 'rtu') {
      readWindows.value.forEach((win) => {
        win.slaveId = props.slaveId || 1
      })
    }
  },
  { immediate: true }
)

watch(
  () => props.connected,
  (connected) => {
    if (!connected) {
      stopAllPolling()
    }
  }
)

onBeforeUnmount(() => {
  stopAllPolling()
})
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
          :disabled="!canEditSlaveId"
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
            :disabled="fc.disabled"
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
        <el-button size="small" @click="readOnce" :icon="Refresh" :disabled="!canRead || activeWindow.loading" :loading="activeWindow.loading && !activeWindow.polling">{{ $t('register.readOnce') }}</el-button>
        <el-button
          size="small"
          :type="activeWindow.polling ? 'danger' : 'primary'"
          @click="togglePolling(activeWindow)"
          :icon="activeWindow.polling ? VideoPause : VideoPlay"
          :disabled="!canRead || activeWindow.loading"
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
            <th
              v-for="header in detailHeaders"
              :key="header.key"
              class="px-2 py-1.5 font-medium border-b border-r border-gray-200"
              :class="[
                header.type === 'value' ? 'text-center w-24' : 'text-left',
                header.type === 'alias' ? 'w-24' : '',
                header.type === 'desc' ? 'w-28' : '',
              ]"
            >
              {{ header.label }}
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
              v-for="cell in detailCells(row)"
              :key="cell.key"
              class="px-2 py-1 border-b border-r border-gray-100"
              :class="[
                cell.type === 'value' ? 'text-center font-mono cursor-pointer select-none transition-colors' : 'text-xs',
                cell.type === 'value' && cell.reg?.changed ? 'bg-yellow-50 text-red-600 font-semibold' : '',
                cell.type === 'value' && !cell.reg?.changed ? 'text-gray-800' : '',
                cell.type === 'value' && cell.reg ? 'hover:bg-blue-50' : '',
                cell.type === 'value' && !cell.reg ? 'bg-gray-50/50' : '',
              ]"
              @dblclick="cell.type === 'value' && cell.reg && startEdit(cell.reg)"
            >
              <input
                v-if="cell.type === 'alias' && cell.reg"
                v-model="cell.reg.alias"
                class="w-full bg-transparent border-none outline-none text-xs text-gray-600 placeholder-gray-300"
                :placeholder="$t('register.aliasPlaceholder')"
              />
              <template v-else-if="cell.type === 'value'">
                <template v-if="cell.reg && editingCell === cell.reg.address">
                  <el-input v-model="editValue" size="small" class="w-full!" autofocus @keyup.enter="confirmEdit(cell.reg)" @blur="confirmEdit(cell.reg)" />
                </template>
                <template v-else-if="cell.reg">
                  {{ formatValue(cell.reg.value, activeWindow.displayFormat) }}
                </template>
              </template>
              <input
                v-else-if="cell.type === 'desc' && cell.reg"
                v-model="cell.reg.desc"
                class="w-full bg-transparent border-none outline-none text-xs text-gray-500 placeholder-gray-300"
                :placeholder="$t('register.descPlaceholder')"
              />
            </td>
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
        <span>{{ $t('register.connection') }}: {{ connected ? connectionId : $t('register.noConnection') }}</span>
        <span>Slave: {{ currentSlaveId }}</span>
        <span>FC: {{ activeWindow.functionCode }}</span>
        <span>{{ $t('register.address') }}: {{ activeWindow.startAddress }}–{{ activeWindow.startAddress + activeWindow.quantity - 1 }}</span>
        <span>{{ $t('register.quantity') }}: {{ activeWindow.quantity }}</span>
      </div>
      <div class="flex items-center gap-4">
        <span v-if="activeWindow.lastError" class="text-red-500">{{ activeWindow.lastError }}</span>
        <span v-if="activeWindow.lastReadAt">{{ $t('register.lastRead') }}: {{ activeWindow.lastReadAt }}</span>
        <span v-if="activeWindow.polling" class="text-green-600">
          ● {{ $t('register.pollingStatus') }} ({{ activeWindow.scanRate }}ms)
        </span>
        <span v-else class="text-gray-400">○ {{ $t('register.idle') }}</span>
        <span>{{ $t('register.format') }}: {{ displayFormats.find(f => f.value === activeWindow.displayFormat)?.label }}</span>
      </div>
    </div>
  </div>
</template>
