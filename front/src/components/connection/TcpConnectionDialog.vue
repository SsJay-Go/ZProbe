<script setup>
import { reactive, watch, computed } from 'vue'
import { ElMessage } from 'element-plus'
import { createTcpConnection } from '../../api/connection'

const props = defineProps({
  modelValue: {
    type: Boolean,
    default: false,
  },
})

const emit = defineEmits(['update:modelValue', 'connected'])

// 弹窗内的连接参数模型：聚焦 Modbus TCP 的必要项。
const form = reactive({
  name: 'TCP-1',
  host: '127.0.0.1',
  port: 502,
  slaveId: 1,
  timeoutMs: 1000,
  retryCount: 2,
})

// 控制提交状态，避免用户重复点击造成并发请求。
const submitting = computed(() => state.submitting)
const state = reactive({
  submitting: false,
})

const localVisible = computed({
  get: () => props.modelValue,
  set: (val) => emit('update:modelValue', val),
})

// 每次重新打开弹窗时可以在此做重置逻辑；当前先保留用户上次输入，方便反复调试。
watch(
  () => props.modelValue,
  (v) => {
    if (!v) return
  }
)

const rules = {
  name: [
    { required: true, message: '请输入连接名称', trigger: 'blur' },
    { min: 2, max: 32, message: '连接名称长度需在 2~32 之间', trigger: 'blur' },
  ],
  host: [
    { required: true, message: '请输入目标 IP 或域名', trigger: 'blur' },
  ],
  port: [
    { required: true, message: '请输入端口号', trigger: 'blur' },
    {
      validator: (_, value, callback) => {
        if (value >= 1 && value <= 65535) callback()
        else callback(new Error('端口范围必须为 1~65535'))
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

let formRef = null
function setFormRef(el) {
  formRef = el
}

async function handleConfirm() {
  if (!formRef || state.submitting) return

  // 提交前先做前端校验，快速反馈输入错误，减少后端无效请求。
  await formRef.validate()

  state.submitting = true
  try {
    const res = await createTcpConnection({ ...form })
    console.log('createTcpConnection response:', res)
    if (!res?.success) {
      throw new Error(res?.message || '创建连接失败')
    }

    ElMessage.success(res.message || 'TCP 连接创建成功')
    emit('connected', res)
    localVisible.value = false
  } catch (error) {
    ElMessage.error(error.message || '创建连接失败')
  } finally {
    state.submitting = false
  }
}
</script>

<template>
  <el-dialog
    v-model="localVisible"
    title=""
    width="640px"
    :close-on-click-modal="false"
    destroy-on-close
    class="[&_.el-dialog]:rounded-[24px] [&_.el-dialog]:p-1 [&_.el-dialog__body]:px-5 [&_.el-dialog__body]:pb-2 [&_.el-dialog__body]:pt-5 [&_.el-dialog__footer]:px-5 [&_.el-dialog__footer]:pb-5 [&_.el-dialog__header]:hidden"
  >
    <section class="text-slate-800">
      <div class="app-dialog-surface px-5 pb-2 pt-4">
        <div class="mb-4 flex items-start justify-between gap-4 border-b border-slate-100 pb-4 max-[820px]:flex-col max-[820px]:pb-3">
          <div class="min-w-0">
            <strong class="block text-[19px] leading-tight">{{ form.name }}</strong>
            <p class="mt-1 text-sm text-slate-500">{{ form.host }}:{{ form.port }}</p>
          </div>
          <div class="flex flex-wrap gap-2 max-[820px]:w-full">
            <span class="app-dialog-chip">Slave {{ form.slaveId }}</span>
            <span class="app-dialog-chip">{{ form.timeoutMs }} ms</span>
            <span class="app-dialog-chip">Retry {{ form.retryCount }}</span>
          </div>
        </div>

        <el-form :model="form" :rules="rules" label-position="top" @submit.prevent :ref="setFormRef">
          <div class="app-form-grid">
            <el-form-item label="连接名称" prop="name">
              <el-input v-model="form.name" placeholder="例如：产线-PLC-1" />
            </el-form-item>

            <el-form-item label="IP / 域名" prop="host">
              <el-input v-model="form.host" placeholder="例如：192.168.1.10" />
            </el-form-item>

            <el-form-item label="端口" prop="port">
              <el-input-number v-model="form.port" :min="1" :max="65535" class="app-dialog-number" />
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
