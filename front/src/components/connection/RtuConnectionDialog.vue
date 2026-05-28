<script setup>
import { reactive, watch, computed } from 'vue'
import { ElMessage } from 'element-plus'
import { createRtuConnection } from '../../api/connection'

const props = defineProps({
  modelValue: {
    type: Boolean,
    default: false,
  },
})

const emit = defineEmits(['update:modelValue', 'connected'])

// RTU 参数和 libmodbus 的 connectRtu 一一对应，避免在前端再造一层无意义映射。
const form = reactive({
  name: 'RTU-1',
  serialPort: 'COM3',
  baudRate: 9600,
  dataBits: 8,
  parity: 'none',
  stopBits: 1,
  slaveId: 1,
  timeoutMs: 1000,
  retryCount: 2,
})

const submitting = computed(() => state.submitting)
const state = reactive({
  submitting: false,
})

const localVisible = computed({
  get: () => props.modelValue,
  set: (val) => emit('update:modelValue', val),
})

watch(
  () => props.modelValue,
  (visible) => {
    if (!visible) return
  }
)

const rules = {
  name: [
    { required: true, message: '请输入连接名称', trigger: 'blur' },
    { min: 2, max: 32, message: '连接名称长度需在 2~32 之间', trigger: 'blur' },
  ],
  serialPort: [
    { required: true, message: '请输入串口路径', trigger: 'blur' },
  ],
  baudRate: [
    {
      validator: (_, value, callback) => {
        if (value >= 1) callback()
        else callback(new Error('波特率必须大于 0'))
      },
      trigger: 'blur',
    },
  ],
  dataBits: [
    {
      validator: (_, value, callback) => {
        if (value >= 5 && value <= 8) callback()
        else callback(new Error('数据位范围必须为 5~8'))
      },
      trigger: 'blur',
    },
  ],
  stopBits: [
    {
      validator: (_, value, callback) => {
        if (value >= 1 && value <= 2) callback()
        else callback(new Error('停止位范围必须为 1~2'))
      },
      trigger: 'blur',
    },
  ],
  slaveId: [
    {
      validator: (_, value, callback) => {
        if (value >= 1 && value <= 247) callback()
        else callback(new Error('Slave ID 范围必须为 1~247'))
      },
      trigger: 'blur',
    },
  ],
  timeoutMs: [
    {
      validator: (_, value, callback) => {
        if (value >= 100 && value <= 120000) callback()
        else callback(new Error('超时范围必须为 100~120000 ms'))
      },
      trigger: 'blur',
    },
  ],
  retryCount: [
    {
      validator: (_, value, callback) => {
        if (value >= 0 && value <= 10) callback()
        else callback(new Error('重试次数范围必须为 0~10'))
      },
      trigger: 'blur',
    },
  ],
}

const parityOptions = [
  { label: 'None', value: 'none' },
  { label: 'Even', value: 'even' },
  { label: 'Odd', value: 'odd' },
]

let formRef = null
function setFormRef(el) {
  formRef = el
}

async function handleConfirm() {
  if (!formRef || state.submitting) return

  await formRef.validate()

  state.submitting = true
  try {
    const res = await createRtuConnection({ ...form })
    if (!res?.success) {
      throw new Error(res?.message || '创建 RTU 连接失败')
    }

    ElMessage.success(res.message || 'RTU 连接创建成功')
    emit('connected', res)
    localVisible.value = false
  } catch (error) {
    ElMessage.error(error.message || '创建 RTU 连接失败')
  } finally {
    state.submitting = false
  }
}
</script>

<template>
  <el-dialog
    v-model="localVisible"
    title=""
    width="680px"
    :close-on-click-modal="false"
    destroy-on-close
    class="[&_.el-dialog]:rounded-3xl [&_.el-dialog]:p-1 [&_.el-dialog__body]:px-5 [&_.el-dialog__body]:pb-2 [&_.el-dialog__body]:pt-5 [&_.el-dialog__footer]:px-5 [&_.el-dialog__footer]:pb-5 [&_.el-dialog__header]:hidden"
  >
    <section class="text-slate-800">
      <div class="app-dialog-surface px-5 pb-2 pt-4">
        <div class="mb-4 flex items-start justify-between gap-4 border-b border-slate-100 pb-4 max-[820px]:flex-col max-[820px]:pb-3">
          <div class="min-w-0">
            <strong class="block text-[19px] leading-tight">{{ form.name }}</strong>
            <p class="mt-1 text-sm text-slate-500">{{ form.serialPort }} · {{ form.baudRate }} baud</p>
          </div>
          <div class="flex flex-wrap gap-2 max-[820px]:w-full">
            <span class="app-dialog-chip">{{ form.dataBits }}{{ form.parity[0].toUpperCase() }}{{ form.stopBits }}</span>
            <span class="app-dialog-chip">Slave {{ form.slaveId }}</span>
            <span class="app-dialog-chip">{{ form.timeoutMs }} ms</span>
          </div>
        </div>

        <el-form :model="form" :rules="rules" label-position="top" @submit.prevent :ref="setFormRef">
          <div class="app-form-grid">
            <el-form-item label="连接名称" prop="name">
              <el-input v-model="form.name" placeholder="例如：产线-485-01" />
            </el-form-item>

            <el-form-item label="串口路径" prop="serialPort">
              <el-input v-model="form.serialPort" placeholder="例如：COM3 或 /dev/ttyUSB0" />
            </el-form-item>

            <el-form-item label="波特率" prop="baudRate">
              <el-input-number v-model="form.baudRate" :min="1" :max="921600" class="app-dialog-number" />
            </el-form-item>

            <el-form-item label="数据位" prop="dataBits">
              <el-select v-model="form.dataBits">
                <el-option :value="5" label="5" />
                <el-option :value="6" label="6" />
                <el-option :value="7" label="7" />
                <el-option :value="8" label="8" />
              </el-select>
            </el-form-item>

            <el-form-item label="校验位" prop="parity">
              <el-select v-model="form.parity">
                <el-option
                  v-for="option in parityOptions"
                  :key="option.value"
                  :label="option.label"
                  :value="option.value"
                />
              </el-select>
            </el-form-item>

            <el-form-item label="停止位" prop="stopBits">
              <el-select v-model="form.stopBits">
                <el-option :value="1" label="1" />
                <el-option :value="2" label="2" />
              </el-select>
            </el-form-item>

            <el-form-item label="Slave ID" prop="slaveId">
              <el-input-number v-model="form.slaveId" :min="1" :max="247" class="app-dialog-number" />
            </el-form-item>

            <el-form-item label="超时 (ms)" prop="timeoutMs">
              <el-input-number v-model="form.timeoutMs" :min="100" :max="120000" :step="100" class="app-dialog-number" />
            </el-form-item>

            <el-form-item label="重试次数" prop="retryCount">
              <el-input-number v-model="form.retryCount" :min="0" :max="10" class="app-dialog-number" />
            </el-form-item>
          </div>
        </el-form>
      </div>
    </section>

    <template #footer>
      <div class="flex w-full justify-end gap-2.5">
        <el-button @click="localVisible = false">取消</el-button>
        <el-button type="primary" :loading="submitting" @click="handleConfirm">创建并连接</el-button>
      </div>
    </template>
  </el-dialog>
</template>