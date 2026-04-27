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
  return request.post('/modbus/read', normalizeReadPayload(payload))
}