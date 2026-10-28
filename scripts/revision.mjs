// Shared by the Luau bundle and Vite so both show the same source revision.
import { execFileSync } from 'node:child_process'
import { fileURLToPath } from 'node:url'
const cwd = fileURLToPath(new URL('..', import.meta.url))
export function revision() {
  let hash = process.env.CF_PAGES_COMMIT_SHA || process.env.CF_COMMIT_SHA || process.env.GITHUB_SHA || ''
  let dirty = false
  try {
    hash = execFileSync('git', ['rev-parse', 'HEAD'], { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
    dirty = !!execFileSync('git', ['status', '--porcelain', '--untracked-files=normal', '--', '.',
      ':(exclude)public/RiftUI.luau', ':(exclude)public/Loader.luau', ':(exclude)public/engine.luau'],
    { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim()
  } catch { /* Source archives can supply a CI commit instead of a .git directory. */ }
  if (!/^[a-f0-9]{40}$/i.test(hash)) return { hash: null, version: 'dev', dirty: true }
  hash = hash.toLowerCase()
  return { hash, version: hash.slice(0, 7) + (dirty ? '-dev' : ''), dirty }
}
