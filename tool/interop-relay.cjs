'use strict'

// Test fixture only. The same pinned JS relay/agent back the host and phone tests.
const { randomBytes } = require('node:crypto')
const { execFileSync } = require('node:child_process')
const { once } = require('node:events')
const { mkdtempSync, readFileSync, rmSync, writeFileSync } = require('node:fs')
const http = require('node:http')
const net = require('node:net')
const { tmpdir } = require('node:os')
const path = require('node:path')
const readline = require('node:readline')
const tls = require('node:tls')

const upstream = '../.upstream/node-tunnel'
const { createRelay } = require(upstream + '/relay.js')
const { createAgent } = require(upstream + '/agent.js')
const { getAgentConfig, getRelayConfig } = require(upstream + '/config.js')

const device = process.argv.includes('--device')
const useTls = process.argv.includes('--tls')
const browser = device && process.argv.includes('--browser')
const cryptKey = randomBytes(16).toString('hex')
const route = 'dirka-interop'
const greeting = Buffer.from([0, 255, 10, 128])
const bind = device ? '0.0.0.0' : '127.0.0.1'
const report = value => process.stdout.write(JSON.stringify(value) + '\n')
console.log = console.info = (...args) => console.error(...args)

async function listen(server, port = 0) {
  server.listen(port, '127.0.0.1')
  await once(server, 'listening')
  return server.address().port
}

async function main() {
  const echo = marker => net.createServer({ allowHalfOpen: true }, socket => {
    socket.on('error', () => socket.destroy())
    socket.write(marker)
    socket.pipe(socket)
  })
  const targetPort = await listen(echo(greeting))
  const secondTarget = browser
    ? http.createServer((request, response) => {
      response.writeHead(200, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' })
      response.end('Dirka forwarded this browser request.\n')
      if (request.url === '/dirka-background-check') console.error('Dirka browser forwarding verified.')
    })
    : echo(Buffer.from([1, ...greeting.subarray(1)]))
  const secondTargetPort = await listen(secondTarget)
  // The JS relay takes a configured fixed port. Reserve one until its startup.
  const reserve = net.createServer()
  const relayPort = await listen(reserve)
  await new Promise(resolve => reserve.close(resolve))
  const relay = () => createRelay(getRelayConfig({
    N_T_RELAY_BIND_HOST: bind,
    N_T_RELAY_PORT: String(relayPort),
    N_T_CRYPT_KEY: cryptKey,
  }))
  let relayServer = relay()
  await relayServer.start()

  let clientPort = relayPort
  let caPath
  if (useTls) {
    const directory = mkdtempSync(path.join(tmpdir(), 'dirka-tls-'))
    process.on('exit', () => rmSync(directory, { recursive: true, force: true }))
    const openssl = args => execFileSync('openssl', args, { cwd: directory, stdio: 'ignore' })
    writeFileSync(path.join(directory, 'server.ext'), 'subjectAltName=DNS:localhost\n')
    openssl(['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
      '-keyout', 'ca.key', '-out', 'ca.pem', '-subj', '/CN=Dirka test CA'])
    openssl(['req', '-new', '-newkey', 'rsa:2048', '-nodes', '-keyout', 'server.key',
      '-out', 'server.csr', '-subj', '/CN=localhost'])
    openssl(['x509', '-req', '-days', '1', '-in', 'server.csr', '-CA', 'ca.pem',
      '-CAkey', 'ca.key', '-CAcreateserial', '-extfile', 'server.ext', '-out', 'server.pem'])
    caPath = path.join(directory, 'ca.der')
    openssl(['x509', '-in', 'ca.pem', '-outform', 'DER', '-out', 'ca.der'])
    const proxy = tls.createServer({
      key: readFileSync(path.join(directory, 'server.key')),
      cert: readFileSync(path.join(directory, 'server.pem')),
      allowHalfOpen: true,
    }, socket => {
      const target = net.connect({ port: relayPort, host: '127.0.0.1', allowHalfOpen: true })
      socket.on('error', () => target.destroy())
      target.on('error', () => socket.destroy())
      socket.on('close', () => target.destroy())
      target.on('close', () => socket.end())
      socket.pipe(target).pipe(socket)
    })
    clientPort = await listen(proxy)
  }

  let agent
  async function startAgent() {
    agent = createAgent(getAgentConfig({
      N_T_RELAY_HOST: '127.0.0.1',
      N_T_RELAY_PORT: String(relayPort),
      N_T_CRYPT_KEY: cryptKey,
      N_T_ROUTE_ID: route,
      N_T_AGENT_DATA_HOST: '127.0.0.1',
      N_T_AGENT_DATA_PORTS: `${targetPort},${secondTargetPort}`,
      N_T_RECONNECT_DELAY_MS: '100',
    }))
    agent.on('fatal', error => { throw error })
    await agent.start()
  }

  const config = { relayPort: clientPort, route, key: cryptKey, caPath }
  if (device) {
    await startAgent()
    console.error('Enter this temporary configuration with the development host’s LAN address and TLS off.')
  }
  report(config)
  if (device && !process.argv.includes('--control')) return
  for await (const line of readline.createInterface({ input: process.stdin })) {
    if (line === 'start-agent') await startAgent()
    if (line === 'stop-agent') await agent.close({ force: true })
    if (line === 'stop-relay') await relayServer.close({ force: true })
    if (line === 'start-relay') {
      relayServer = relay()
      await relayServer.start()
    }
    report({ done: line })
  }
  process.exit(0)
}

main().catch(error => { console.error(error); process.exit(1) })
