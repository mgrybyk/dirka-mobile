'use strict'

const { execFileSync } = require('node:child_process')
const { setTimeout: delay } = require('node:timers/promises')

const [serial, sampleCount = '13', intervalSeconds = '600', ...extra] = process.argv.slice(2)
const count = Number(sampleCount)
const intervalMs = Number(intervalSeconds) * 1000
if (!serial || extra.length || !Number.isSafeInteger(count) || count < 1 ||
    !Number.isSafeInteger(intervalMs) || intervalMs < 1000 || intervalMs > 2_147_483_647) {
  console.error('Usage: node tool/device-memory.cjs DEVICE_SERIAL [SAMPLES=13] [INTERVAL_SECONDS=600]')
  process.exit(2)
}

const packageName = 'com.mgrybyk.dirka'
const adb = (...args) => execFileSync('adb', ['-s', serial, ...args], {
  encoding: 'utf8',
  timeout: 30_000,
}).trim()

function runningPid() {
  let pid
  try {
    pid = adb('shell', 'pidof', packageName)
  } catch (error) {
    if (error.status !== 1 || error.stderr?.trim()) throw error
  }
  if (!/^\d+$/.test(pid ?? '')) {
    throw new Error('Expected one running Dirka process. Open Dirka and start a new capture.')
  }
  return pid
}

async function main() {
  const pid = runningPid()
  const startedAt = performance.now()
  for (let index = 0; index < count; index++) {
    if (index > 0) {
      await delay(Math.max(0, startedAt + index * intervalMs - performance.now()))
    }
    const timestamp = new Date().toISOString()
    const memory = adb('shell', 'dumpsys', 'meminfo', '-d', pid)
    if (runningPid() !== pid || !memory.includes(`MEMINFO in pid ${pid} [${packageName}]`)) {
      throw new Error('Dirka changed processes during capture. Start a new capture for the current process.')
    }
    process.stdout.write(`\n${timestamp} | Sample ${index + 1}/${count} | PID ${pid}\n${memory}\n`)
  }
}

main().catch(error => {
  console.error(error.message)
  process.exitCode = 1
})
