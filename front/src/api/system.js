import request from '../utils/request'

export function fetchTrafficLogs() {
  return request.get('/system/traffic')
}

export function clearTrafficLogs() {
  return request.post('/system/traffic/clear')
}
