import ws from 'k6/ws'
import {
  check
} from 'k6'

export default function () {
  const DMTR_API_KEY = '${api_key}'
  const url = '${url}'

  const payload = {
    jsonrpc: '2.0',
    method: 'queryNetwork/tip',
  }

  const params = {
    headers: {
      'dmtr-api-key': DMTR_API_KEY,
    },
  }

  const response = ws.connect(url, params, function (socket) {
    socket.on('open', function () {
      console.log('Connected. Sending request.')
      socket.send(JSON.stringify(payload))
    })

    socket.on('message', function (data) {
      console.log('Received:', data)
      const json = JSON.parse(data)

      check(json,
        {
          'has result': (r) => r.result !== undefined,
          'result has slot': (r) => r.result?.slot > 0,
        })

      socket.close()
    })

    socket.on('error', function (e) {
      console.log('WebSocket error:', e)
    })
  })

  check(response,
    {
      'status is 101': (r) => r && r.status === 101
    })
}
