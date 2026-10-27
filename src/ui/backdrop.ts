// Stand-in game scenes behind the ScreenGui: a Roblox baseplate in three lighting setups,
// so a hub can be checked for legibility over bright, dark and busy backgrounds.

export type BackdropName = 'day' | 'night' | 'snow'

interface Palette {
  skyTop: string
  skyBottom: string
  ground: string
  groundFar: string
  grid: string
  parts: string[]
  shade: number
}

const PALETTES: Record<BackdropName, Palette> = {
  day: { skyTop: '#5d9fdc', skyBottom: '#cfe6f7', ground: '#6f7378', groundFar: '#9a9da1', grid: 'rgba(0,0,0,0.10)', parts: ['#c4281c', '#0d69ac', '#f5cd30', '#4b974b', '#a3a2a5'], shade: 0.78 },
  night: { skyTop: '#060a18', skyBottom: '#1b2440', ground: '#24272d', groundFar: '#30343b', grid: 'rgba(255,255,255,0.05)', parts: ['#6b1a14', '#0b3b66', '#7a6418', '#244d24', '#4c4c50'], shade: 0.7 },
  snow: { skyTop: '#bcd6ee', skyBottom: '#f4f8fb', ground: '#eef2f5', groundFar: '#f8fafc', grid: 'rgba(0,0,0,0.05)', parts: ['#e8e8e8', '#ffffff', '#d9e4ee', '#c9d6e3', '#ffffff'], shade: 0.88 },
}

function shadeHex(hex: string, f: number) {
  const n = parseInt(hex.slice(1), 16)
  const r = Math.round(((n >> 16) & 255) * f)
  const g = Math.round(((n >> 8) & 255) * f)
  const b = Math.round((n & 255) * f)
  return `rgb(${r},${g},${b})`
}

export function drawBackdrop(canvas: HTMLCanvasElement, w: number, h: number, name: BackdropName) {
  const dpr = Math.min(window.devicePixelRatio || 1, 2)
  canvas.width = Math.round(w * dpr)
  canvas.height = Math.round(h * dpr)
  const ctx = canvas.getContext('2d')!
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0)
  const p = PALETTES[name]
  const horizon = h * 0.46
  const sky = ctx.createLinearGradient(0, 0, 0, horizon)
  sky.addColorStop(0, p.skyTop)
  sky.addColorStop(1, p.skyBottom)
  ctx.fillStyle = sky
  ctx.fillRect(0, 0, w, horizon + 1)
  if (name === 'night') {
    let seed = 7
    const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647)
    ctx.fillStyle = 'rgba(255,255,255,0.7)'
    for (let i = 0; i < 140; i++) ctx.fillRect(rnd() * w, rnd() * horizon * 0.9, rnd() < 0.15 ? 2 : 1, 1)
  }
  const ground = ctx.createLinearGradient(0, horizon, 0, h)
  ground.addColorStop(0, p.groundFar)
  ground.addColorStop(1, p.ground)
  ctx.fillStyle = ground
  ctx.fillRect(0, horizon, w, h - horizon)

  // baseplate grid in perspective, vanishing at the horizon centre
  const vx = w / 2
  ctx.strokeStyle = p.grid
  ctx.lineWidth = 1
  // radial lines start a little below the horizon so they don't pile up into a dark point
  const start = (h - horizon) * 0.06
  for (let i = -40; i <= 40; i++) {
    const ex = vx + i * w * 0.09
    const ey = h * 1.6
    const f = start / (ey - horizon)
    ctx.beginPath()
    ctx.moveTo(vx + (ex - vx) * f, horizon + start)
    ctx.lineTo(ex, ey)
    ctx.stroke()
  }
  for (let z = 1; z < 60; z++) {
    const y = horizon + (h - horizon) * (1 / (1 + 30 / (z * z * 0.6)))
    ctx.beginPath()
    ctx.moveTo(0, y)
    ctx.lineTo(w, y)
    ctx.stroke()
  }

  // a few parts, drawn as simple shaded boxes
  const part = (cx: number, base: number, bw: number, bh: number, depth: number, color: string) => {
    ctx.fillStyle = shadeHex(color, p.shade)
    ctx.beginPath()
    ctx.moveTo(cx + bw / 2, base)
    ctx.lineTo(cx + bw / 2 + depth, base - depth * 0.5)
    ctx.lineTo(cx + bw / 2 + depth, base - bh - depth * 0.5)
    ctx.lineTo(cx + bw / 2, base - bh)
    ctx.closePath()
    ctx.fill()
    ctx.fillStyle = shadeHex(color, Math.min(1.12, p.shade + 0.3))
    ctx.beginPath()
    ctx.moveTo(cx - bw / 2, base - bh)
    ctx.lineTo(cx + bw / 2, base - bh)
    ctx.lineTo(cx + bw / 2 + depth, base - bh - depth * 0.5)
    ctx.lineTo(cx - bw / 2 + depth, base - bh - depth * 0.5)
    ctx.closePath()
    ctx.fill()
    ctx.fillStyle = color
    ctx.fillRect(cx - bw / 2, base - bh, bw, bh)
  }
  const u = h / 720
  part(w * 0.16, h * 0.74, 150 * u, 60 * u, 40 * u, p.parts[2])
  part(w * 0.73, h * 0.66, 120 * u, 150 * u, 46 * u, p.parts[0])
  part(w * 0.86, h * 0.6, 70 * u, 210 * u, 30 * u, p.parts[1])
  part(w * 0.38, h * 0.57, 90 * u, 70 * u, 26 * u, p.parts[3])
  part(w * 0.3, h * 0.95, 200 * u, 18 * u, 60 * u, p.parts[4])
}
