<script setup>
import { ref, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import {
  ArrowDown, Monitor, Connection, Setting, DataLine, Document,
  Edit, View, Tools, QuestionFilled, Link, Refresh, Search,
  Histogram, List, Warning, Cpu,
} from '@element-plus/icons-vue'
import RegisterView from '../views/RegisterView.vue'

const { t, locale } = useI18n()

function switchLang(lang) {
  locale.value = lang
  localStorage.setItem('locale', lang)
}

const activeTab = ref('connection')
const activeSubTab = ref('new-tcp')

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
            class="nav-btn flex items-center gap-1.5 px-3 py-1.5 rounded-md text-[13px] transition-all whitespace-nowrap cursor-pointer border-none outline-none relative"
            :class="activeTab === tab.name
              ? 'bg-blue-50 text-blue-600 font-medium shadow-xs'
              : 'bg-transparent text-gray-500 hover:bg-gray-100/80 hover:text-gray-700'"
          >
            <el-icon :size="15"><component :is="tab.icon" /></el-icon>
            {{ tab.label }}
            <el-icon :size="10" class="ml-0.5 opacity-40 transition-transform" :class="{ 'rotate-180': false }"><ArrowDown /></el-icon>
          </button>
          <template #dropdown>
            <el-dropdown-menu class="nav-dropdown">
              <template v-for="(child, idx) in tab.children" :key="idx">
                <div v-if="child.divider" class="mx-2 my-1.5 border-t border-gray-100" />
                <el-dropdown-item
                  v-else
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
          <button class="flex items-center gap-1 px-2 py-1 rounded text-xs text-gray-500 hover:bg-gray-100 cursor-pointer border-none outline-none bg-transparent transition-colors">
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
        <el-tag type="danger" size="small" effect="dark" round>{{ $t('app.disconnected') }}</el-tag>
      </div>
    </div>

    <!-- 主内容区 -->
    <el-main class="bg-gray-50 p-0! overflow-hidden">
      <RegisterView />
    </el-main>
  </el-container>
</template>

<style scoped>
/* 导航按钮过渡 */
.nav-btn {
  transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}
.nav-btn:active {
  transform: scale(0.97);
}
</style>

<style>
/* 下拉菜单全局样式覆盖 */
.nav-dropdown.el-dropdown-menu {
  padding: 6px;
  border-radius: 10px;
  border: 1px solid #e5e7eb;
  box-shadow: 0 8px 24px -4px rgba(0, 0, 0, 0.08), 0 2px 8px -2px rgba(0, 0, 0, 0.04);
  min-width: 180px;
}

.nav-dropdown-item.el-dropdown-menu__item {
  padding: 8px 12px;
  border-radius: 6px;
  font-size: 13px;
  color: #4b5563;
  line-height: 1.5;
  transition: all 0.15s ease;
  margin: 1px 0;
}

.nav-dropdown-item.el-dropdown-menu__item:hover {
  background: #f0f7ff;
  color: #2563eb;
}

.nav-dropdown-item.el-dropdown-menu__item.is-selected {
  background: #eff6ff;
  color: #2563eb;
  font-weight: 500;
}

.nav-dropdown-item.el-dropdown-menu__item.is-selected::before {
  content: '';
  display: inline-block;
  width: 4px;
  height: 4px;
  border-radius: 50%;
  background: #2563eb;
  margin-right: 6px;
  vertical-align: middle;
}
</style>
