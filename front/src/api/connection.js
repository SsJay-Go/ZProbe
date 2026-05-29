import request from '../utils/request'

/**
 * 创建 TCP 连接。
 * 这里统一封装请求路径与 payload 结构，页面组件只负责采集参数和展示状态。
 * @param {Object} payload
 * @param {string} payload.name 连接名称
 * @param {string} payload.host 目标 IP 或域名
 * @param {number} payload.port 目标端口
 * @param {number} payload.slaveId Modbus 从站地址
 * @param {number} payload.timeoutMs 请求超时（毫秒）
 * @param {number} payload.retryCount 失败重试次数
 */
export function createTcpConnection(payload) {
  return request.post('/connection/connect', {
    type: 'tcp',
    ...payload,
  })
}

/**
 * 创建 RTU 连接。
 * @param {Object} payload
 * @param {string} payload.name 连接名称
 * @param {string} payload.serialPort 串口路径，例如 COM3 或 /dev/ttyUSB0
 * @param {number} payload.baudRate 波特率
 * @param {'none'|'even'|'odd'} payload.parity 校验位
 * @param {number} payload.dataBits 数据位
 * @param {number} payload.stopBits 停止位
 * @param {number} payload.slaveId Modbus 从站地址
 * @param {number} payload.timeoutMs 请求超时（毫秒）
 * @param {number} payload.retryCount 失败重试次数
 */
export function createRtuConnection(payload) {
  return request.post('/connection/connect', {
    type: 'rtu',
    ...payload,
  })
}

/**
 * 断开连接。
 * @param {string} connectionId 后端返回的连接 ID
 */
export function disconnectConnection(connectionId) {
  return request.post('/connection/disconnect', {
    connectionId,
  })
}

export function fetchConnectionState(connectionId) {
  return request.get(`/connection/state/${encodeURIComponent(connectionId)}`)
}
