<script setup>
import { ref, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { ElMessage } from 'element-plus'
import {
  ArrowDown, Monitor, Connection, Setting, DataLine, Document,
  Edit, View, Tools, QuestionFilled, Link, Refresh, Search,
  Histogram, List, Warning, Cpu,
} from '@element-plus/icons-vue'
import RegisterView from '../views/RegisterView.vue'
import TcpConnectionDialog from '../components/connection/TcpConnectionDialog.vue'

const { t, locale } = useI18n()

function switchLang(lang) {
  locale.value = lang
  localStorage.setItem('locale', lang)
}

const activeTab = ref('connection')
const activeSubTab = ref('new-tcp')
const tcpDialogVisible = ref(false)
const connectionState = ref({
  connected: false,
  name: '',
})

const tabs = computed(() => [
  {
    name: 'connection', label: t('nav.connection'), icon: Link,
    children: [
      { name: 'new-tcp', label: t('nav.newTcp') },
      { name: 'new-rtu', label: t('nav.newRtu') },
      { name: 'new-ascii', label: t('nav.newAscii') },
      { divider: true },
      { name: 'manager', label: t('nav.manager') },
      { name: 'scan-port', label: t('nav.scanPort') },
    ]
  },
  {
    name: 'setup', label: t('nav.setup'), icon: Edit,
    children: [
      { name: 'new-read', label: t('nav.newRead') },
      { name: 'new-write', label: t('nav.newWrite') },
      { name: 'batch', label: t('nav.batch') },
      { divider: true },
      { name: 'import-export', label: t('nav.importExport') },
    ]
  },
  {
    name: 'functions', label: t('nav.functions'), icon: Cpu,
    children: [
      { name: 'fc01', label: t('nav.fc01') },
      { name: 'fc02', label: t('nav.fc02') },
      { name: 'fc03', label: t('nav.fc03') },
      { name: 'fc04', label: t('nav.fc04') },
      { divider: true },
      { name: 'fc05', label: t('nav.fc05') },
      { name: 'fc06', label: t('nav.fc06') },
      { name: 'fc0f', label: t('nav.fc0f') },
      { name: 'fc10', label: t('nav.fc10') },
      { name: 'fc17', label: t('nav.fc17') },
      { divider: true },
      { name: 'custom-frame', label: t('nav.customFrame') },
    ]
  },
  {
    name: 'display', label: t('nav.display'), icon: View,
    children: [
      { name: 'format', label: t('nav.format') },
      { name: 'endian', label: t('nav.endian') },
      { name: 'table-view', label: t('nav.tableView') },
      { name: 'map-view', label: t('nav.mapView') },
      { name: 'highlight', label: t('nav.highlight') },
    ]
  },
  {
    name: 'monitor', label: t('nav.monitor'), icon: Monitor,
    children: [
      { name: 'polling', label: t('nav.polling') },
      { name: 'chart', label: t('nav.chart') },
      { name: 'record', label: t('nav.record') },
      { divider: true },
      { name: 'traffic', label: t('nav.traffic') },
      { name: 'error-stats', label: t('nav.errorStats') },
    ]
  },
  {
    name: 'tools', label: t('nav.tools'), icon: Tools,
    children: [
      { name: 'crc-calc', label: t('nav.crcCalc') },
      { name: 'addr-convert', label: t('nav.addrConvert') },
      { name: 'data-convert', label: t('nav.dataConvert') },
      { divider: true },
      { name: 'slave-sim', label: t('nav.slaveSim') },
      { name: 'stress-test', label: t('nav.stressTest') },
    ]
  },
  {
    name: 'help', label: t('nav.help'), icon: QuestionFilled,
    children: [
      { name: 'protocol-ref', label: t('nav.protocolRef') },
      { name: 'shortcuts', label: t('nav.shortcuts') },
      { name: 'about', label: t('nav.about') },
    ]
  },
])

function handleTabCommand(command) {
  const [tab, sub] = command.split('/')
  activeTab.value = tab
  activeSubTab.value = sub

  // 只在用户点击“连接 -> 新建 TCP 连接”菜单项时弹出参数窗口。
  if (tab === 'connection' && sub === 'new-tcp') {
    tcpDialogVisible.value = true
  }
}

function handleTabClick(tab) {
  activeTab.value = tab.name
  const firstReal = tab.children.find(c => !c.divider)
  if (firstReal) activeSubTab.value = firstReal.name
}

const currentTab = computed(() => tabs.find(t => t.name === activeTab.value))
const currentSubLabel = computed(() => {
  const tab = currentTab.value
  if (!tab) return ''
  const child = tab.children.find(c => c.name === activeSubTab.value)
  return child?.label || ''
})

function handleTcpConnected(payload) {
  // 这里仅维护 UI 状态；连接真实生命周期以后可迁移到 Pinia 统一管理。
  connectionState.value = {
    connected: true,
    name: payload?.connection?.name || 'TCP',
  }
  ElMessage.success(`已连接: ${connectionState.value.name}`)
}
</script>

<template>
  <el-container class="h-full" direction="vertical">
    <!-- 顶部导航栏 -->
    <div class="flex items-center border-b border-gray-200 bg-white px-3 h-11 shrink-0">
      <div class="flex items-center gap-1.5 mr-4 shrink-0">
        <el-icon :size="18" class="text-blue-500"><Connection /></el-icon>
        <span class="text-[13px] font-semibold text-gray-800 whitespace-nowrap">{{ $t('app.title') }}</span>
      </div>

      <div class="flex items-center flex-1">
        <el-dropdown
          v-for="tab in tabs"
          :key="tab.name"
          trigger="hover"
          @command="handleTabCommand"
          placement="bottom-start"
          :show-timeout="50"
          :hide-timeout="200"
          :popper-options="{ modifiers: [{ name: 'offset', options: { offset: [0, 4] } }] }"
        >
          <button
            @click="handleTabClick(tab)"
            class="app-nav-button"
            :class="activeTab === tab.name
              ? 'app-nav-button-active'
              : 'app-nav-button-idle'"
          >
            <el-icon :size="15"><component :is="tab.icon" /></el-icon>
            {{ tab.label }}
            <el-icon :size="10" class="ml-0.5 opacity-40 transition-transform" :class="{ 'rotate-180': false }"><ArrowDown /></el-icon>
          </button>
          <template #dropdown>
            <el-dropdown-menu class="nav-dropdown">
              <template v-for="(child, idx) in tab.children">
                <div v-if="child.divider" :key="`divider-${idx}`" class="mx-2 my-1.5 border-t border-gray-100" />
                <el-dropdown-item
                  v-else
                  :key="`item-${idx}`"
                  :command="`${tab.name}/${child.name}`"
                  class="nav-dropdown-item"
                  :class="{ 'is-selected': activeTab === tab.name && activeSubTab === child.name }"
                >
                  {{ child.label }}
                </el-dropdown-item>
              </template>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
      </div>

      <div class="flex items-center gap-2 ml-3 shrink-0">
        <el-dropdown trigger="click" @command="switchLang" placement="bottom-end">
          <button class="app-nav-plain-button">
            {{ locale === 'zh' ? '中' : 'En' }}
            <el-icon :size="10"><ArrowDown /></el-icon>
          </button>
          <template #dropdown>
            <el-dropdown-menu class="nav-dropdown">
              <el-dropdown-item command="zh" class="nav-dropdown-item" :class="{ 'is-selected': locale === 'zh' }">{{ $t('lang.zh') }}</el-dropdown-item>
              <el-dropdown-item command="en" class="nav-dropdown-item" :class="{ 'is-selected': locale === 'en' }">{{ $t('lang.en') }}</el-dropdown-item>
            </el-dropdown-menu>
          </template>
        </el-dropdown>
        <el-tag
          :type="connectionState.connected ? 'success' : 'danger'"
          size="small"
          effect="dark"
          round
        >
          {{ connectionState.connected ? $t('app.connected') : $t('app.disconnected') }}
        </el-tag>
      </div>
    </div>

    <!-- 主内容区 -->
    <el-main class="bg-gray-50 p-0! overflow-hidden">
      <RegisterView />
    </el-main>

    <TcpConnectionDialog
      v-model="tcpDialogVisible"
      @connected="handleTcpConnected"
    />
  </el-container>
</template>
