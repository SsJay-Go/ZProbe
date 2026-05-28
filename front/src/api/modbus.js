import request from '../utils/request'

function normalizeReadPayload(payload) {
  const next = {
    connectionId: payload.connectionId,
    target: payload.target,
    startAddress: payload.startAddress,
    quantity: payload.quantity,
  }

  if (payload.slaveId != null) {
    next.slaveId = payload.slaveId
  }

  return next
}

export function readRegisters(payload) {
  const timeout = Number(payload.timeoutMs)
  const config = Number.isFinite(timeout)
    ? { timeout: Math.max(1000, timeout + 2000) }
    : undefined

  return request.post('/modbus/read', normalizeReadPayload(payload), config)
}

function normalizeWritePayload(payload) {
  const next = {
    connectionId: payload.connectionId,
    target: payload.target,
    startAddress: payload.startAddress,
  }

  if (payload.slaveId != null) {
    next.slaveId = payload.slaveId
  }

  if (payload.value != null) {
    next.value = payload.value
  }

  if (Array.isArray(payload.values)) {
    next.values = payload.values
  }

  return next
}

export function writeRegisters(payload) {
  const timeout = Number(payload.timeoutMs)
  const config = Number.isFinite(timeout)
    ? { timeout: Math.max(1000, timeout + 2000) }
    : undefined

  return request.post('/modbus/write', normalizeWritePayload(payload), config)
}

export function writeReadRegisters(payload) {
  const timeout = Number(payload.timeoutMs)
  const config = Number.isFinite(timeout)
    ? { timeout: Math.max(1000, timeout + 2000) }
    : undefined

  return request.post('/modbus/write-read', {
    connectionId: payload.connectionId,
    slaveId: payload.slaveId ?? null,
    writeStartAddress: payload.writeStartAddress,
    values: payload.values,
    readStartAddress: payload.readStartAddress,
    readQuantity: payload.readQuantity,
  }, config)
}