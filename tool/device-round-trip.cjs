'use strict'

// adb forward opens the phone's loopback socket from adbd, outside Dirka.
const { execFileSync } = require('node:child_process')
const { connect } = require('node:net')

const [serial, port = '18080'] = process.argv.slice(2)
if (!serial || !/^[0-9]+$/.test(port) || Number(port) < 1 || Number(port) > 65535) {
  console.error('Usage: node tool/device-round-trip.cjs DEVICE_SERIAL [DIRKA_PORT]')
  process.exit(2)
}
const adb = (...args) => execFileSync('adb', ['-s', serial, ...args], { encoding: 'utf8' }).trim()
const payload = Buffer.from(Array.from({ length: 65536 }, (_, index) => index & 255))
const expected = Buffer.concat([Buffer.from([0, 255, 10, 128]), payload])

async function main() {
  const forwarded = 'tcp:' + adb('forward', 'tcp:0', 'tcp:' + port)
  let stream
  try {
    await new Promise((resolve, reject) => {
      stream = connect({ host: '127.0.0.1', port: Number(forwarded.slice(4)) }, () => stream.write(payload))
      const received = []
      let length = 0
      stream.setTimeout(5000, () => reject(new Error('Timed out waiting for the echo')))
      stream.on('error', reject)
      stream.on('end', () => reject(new Error('The tunnel closed before the echo completed')))
      stream.on('data', bytes => {
        received.push(bytes)
        length += bytes.length
        if (length < expected.length) return
        if (Buffer.concat(received).equals(expected)) resolve()
        else reject(new Error('The echoed bytes differ from the fixture payload'))
      })
    })
    console.log('Dirka forwarded and verified 65536 binary bytes and the server greeting.')
  } finally {
    stream?.destroy()
    adb('forward', '--remove', forwarded)
  }
}

main().catch(error => {
  console.error(error.message)
  process.exitCode = 1
})
