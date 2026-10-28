// node scripts/config/pack.mjs <plain-config.json> <encrypted.json> <hub-id> [name]
// Read the 32-byte Base64 key from RIFT_CONFIG_KEY; never put it in command arguments.
import { readFileSync, writeFileSync } from 'node:fs'
import { randomBytes } from 'node:crypto'
import { encryptConfig } from './crypto.mjs'
const [input, output, hub, name = 'remote'] = process.argv.slice(2)
if (input === '--generate-key') console.log(randomBytes(32).toString('base64'))
else {
  if (!input || !output || !hub) throw Error('Usage: pack.mjs <plain-config.json> <encrypted.json> <hub-id> [name]')
  const data = JSON.parse(readFileSync(input, 'utf8'))
  const payload = data.Hub ? data : { Hub: hub, Name: name, Data: data }
  if (payload.Hub !== hub || !payload.Data || !payload.Data.Flags || typeof payload.Data.Flags !== 'object') throw Error('Invalid config or hub ID')
  writeFileSync(output, JSON.stringify(encryptConfig(payload, process.env.RIFT_CONFIG_KEY)) + '\n', { mode: 0o600 })
  console.log('Encrypted config written to ' + output)
}
