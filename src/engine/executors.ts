// Pretend-executors for testing how a hub degrades. Names are made up; the percentages are
// the share of the sUNC functions below that each profile keeps working.

export const SUNC = [
  'gethui', 'cloneref', 'compareinstances', 'checkcaller', 'newcclosure', 'iscclosure', 'islclosure',
  'getrawmetatable', 'setrawmetatable', 'setreadonly', 'isreadonly', 'getconnections', 'firesignal',
  'protectgui', 'queue_on_teleport', 'loadstring', 'loadfile', 'dofile', 'writefile', 'appendfile',
  'readfile', 'isfile', 'isfolder', 'makefolder', 'delfile', 'delfolder', 'listfiles', 'getcustomasset',
  'request', 'http_request', 'setclipboard', 'getclipboard', 'crypt', 'base64_encode', 'base64_decode',
  'getgenv', 'getrenv', 'getreg', 'getthreadidentity', 'setthreadidentity', 'printidentity',
  'identifyexecutor', 'isrbxactive', 'rconsoleprint',
]

export interface ExecutorProfile {
  id: string
  label: string
  name: string
  off: string[]
  broken: string[]
}

const ALIASES: Record<string, string[]> = {
  gethui: ['get_hidden_gui'],
  protectgui: ['protect_gui', 'syn'],
  queue_on_teleport: ['queueonteleport'],
  getcustomasset: ['getsynasset'],
  request: ['http'],
  setclipboard: ['toclipboard', 'setrbxclipboard'],
  base64_encode: ['base64'],
  getthreadidentity: ['getidentity', 'getthreadcontext'],
  setthreadidentity: ['setidentity'],
  setreadonly: ['makereadonly'],
  identifyexecutor: ['getexecutorname'],
  isrbxactive: ['iswindowactive'],
  rconsoleprint: ['rconsoleclear', 'rconsolecreate', 'rconsoledestroy'],
}

function withAliases(names: string[]) {
  return names.flatMap((n) => [n, ...(ALIASES[n] ?? [])])
}

function profile(id: string, name: string, off: string[], broken: string[] = []): ExecutorProfile {
  const working = SUNC.filter((f) => !off.includes(f) && !broken.includes(f)).length
  const pct = Math.round((working / SUNC.length) * 100)
  return { id, label: `${name} · ${pct}%`, name, off: withAliases(off), broken }
}

const KEEP_2 = ['loadstring']

export const EXECUTORS: ExecutorProfile[] = [
  profile('full', 'RiftSim 1.0', []),
  profile('typical', 'MidExec 3.2', ['getconnections', 'firesignal', 'protectgui', 'queue_on_teleport', 'checkcaller', 'newcclosure', 'iscclosure', 'islclosure'], ['listfiles']),
  profile('budget', 'FreeExec 0.9', [
    'gethui', 'cloneref', 'compareinstances', 'checkcaller', 'newcclosure', 'iscclosure', 'islclosure',
    'getrawmetatable', 'setrawmetatable', 'setreadonly', 'isreadonly', 'getconnections', 'firesignal',
    'protectgui', 'queue_on_teleport', 'getcustomasset', 'delfile', 'delfolder', 'listfiles', 'http_request',
    'crypt', 'base64_encode', 'base64_decode', 'getreg', 'setthreadidentity', 'rconsoleprint',
  ], ['request', 'setclipboard']),
  // it runs scripts. that's about it.
  profile('potato', 'PotatoExec 0.0.1', SUNC.filter((f) => !KEEP_2.includes(f))),
]

export function profileSpec(p: ExecutorProfile) {
  return `name=${p.name};off=${p.off.join(',')};broken=${p.broken.join(',')}`
}
