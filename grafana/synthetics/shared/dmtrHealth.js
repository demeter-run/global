import http from 'k6/http'
import { check } from 'k6'

export default function () {
  const DMTR_API_KEY = '${api_key}'
  const url = '${url}/dmtr_health'

  const params = {
    headers: {
      'dmtr-api-key': DMTR_API_KEY,
    },
    tags: { name: 'dmtr_health' },
  }

  const res = http.get(url, params)

  console.log('Response status:', res.status)
  console.log('Response body:', res.body)

  check(res, {
    'status is 200': (r) => r.status === 200,
    'body is not empty': (r) => (r.body || '').length > 0,
    'body says OK': (r) => (r.body || '').trim().toUpperCase() === 'OK',
  })
}
