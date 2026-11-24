'use strict'

const { execFileSync } = require('node:child_process')
const { readFileSync, readdirSync, writeFileSync } = require('node:fs')
const path = require('node:path')

const root = path.resolve(__dirname, '..')
const target = 'aarch64-linux-android'
const output = path.join(root, 'native/third_party_licenses.json')
const licenses = new Map()

for (const manifest of ['native/Cargo.toml', '.upstream/node-tunnel/rust/Cargo.toml']) {
  const metadata = JSON.parse(execFileSync('cargo', [
    'metadata', '--locked', '--format-version', '1', '--filter-platform', target,
    '--manifest-path', manifest,
  ], { cwd: root, encoding: 'utf8' }))
  const used = new Set(metadata.resolve.nodes.map(node => node.id))
  for (const dependency of metadata.packages) {
    if (!dependency.source || !used.has(dependency.id)) continue

    const directory = path.dirname(dependency.manifest_path)
    const files = new Set(readdirSync(directory, { withFileTypes: true })
      .filter(file => file.isFile() && /^(licen[cs]e|copying|notice|copyright|unlicense)([_.-]|$)/i.test(file.name))
      .map(file => file.name))
    if (dependency.license_file) files.add(dependency.license_file)
    if (files.size === 0) {
      throw new Error(`No license texts found for ${dependency.name} ${dependency.version}`)
    }

    for (const file of files) {
      const text = readFileSync(path.resolve(directory, file), 'utf8').trimEnd()
      if (!licenses.has(text)) licenses.set(text, new Set())
      licenses.get(text).add(`${dependency.name} ${dependency.version}`)
    }
  }
}

const grouped = Array.from(licenses, ([text, packages]) => ({ packages: [...packages].sort(), text }))
grouped.sort((a, b) => {
  const first = a.packages.join(',') + '\n' + a.text
  const second = b.packages.join(',') + '\n' + b.text
  return first < second ? -1 : first > second ? 1 : 0
})
const expected = JSON.stringify(grouped, null, 2) + '\n'
if (process.argv.includes('--check')) {
  if (readFileSync(output, 'utf8') !== expected) {
    console.error('Rust license notices are outdated. Run node tool/native-licenses.cjs.')
    process.exitCode = 1
  }
} else {
  writeFileSync(output, expected)
}
