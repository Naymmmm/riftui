// Assembles the Luau artifacts the simulator and executors load:
//   public/engine.luau  - the emulated Roblox client (engine/*.luau, each file in its own scope)
//   public/RiftUI.luau  - the library, with the generated Lucide index inlined
//   public/Loader.luau  - commit-aware executor entry point
import { readFileSync, readdirSync, writeFileSync, mkdirSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import { revision } from './revision.mjs'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
mkdirSync(join(root, 'public'), { recursive: true })

const files = readdirSync(join(root, 'engine')).filter((f) => f.endsWith('.luau')).sort()
const parts = files.map((f) => {
  const src = readFileSync(join(root, 'engine', f), 'utf8')
  if (f.startsWith('00-') || f.startsWith('99-')) return `-- ${f}\n${src}`
  return `-- ${f}\ndo\n${src}\nend`
})
writeFileSync(join(root, 'public/engine.luau'), parts.join('\n'))

const icons = readFileSync(join(root, 'lib/generated/icons.luau'), 'utf8').replace(/^--.*\n/, '').replace(/^return /, '')
const build = revision()
const lib = readFileSync(join(root, 'lib/RiftUI.luau'), 'utf8').replace('Version = "dev", --@@VERSION@@', 'Version = ' + JSON.stringify(build.version) + ',')
if (!lib.includes('--@@ICONS@@')) throw new Error('lib/RiftUI.luau is missing the --@@ICONS@@ marker')
writeFileSync(join(root, 'public/RiftUI.luau'), lib.replace('--@@ICONS@@', `local ICON_INDEX = ${icons.trim()}`))
writeFileSync(join(root, 'public/Loader.luau'), readFileSync(join(root, 'lib/Loader.luau'), 'utf8'))
console.log(`bundled loader, engine (${files.length} files) and RiftUI`)
