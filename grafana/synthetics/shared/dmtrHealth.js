import http from 'k6/http'
import { check, fail } from 'k6'

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

  // Update assertion dashboard based on response
  const ok = check(res, {
    'status is 200': (r) => r.status === 200,
    'body says OK': (r) => {
      const body = typeof r.body === 'string' ? r.body : String.fromCharCode.apply(null, new Uint8Array(r.body))
      return body.trim().toUpperCase() === 'OK'
    },
  })

  if (!ok) {
    const body = typeof res.body === 'string' ? res.body : String.fromCharCode.apply(null, new Uint8Array(res.body))
    fail(`Health check failed: status=$${res.status}, body=$${body}`)
  }
}
