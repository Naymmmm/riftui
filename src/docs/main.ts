import './style.css'
import { pages, groups, getPage, type DocPage, type DocSection } from './content'
import { themes } from './demos'
import { icon } from '../ui/icons'
import github from 'lucide-static/icons/code.svg?raw'
import external from 'lucide-static/icons/arrow-up-right.svg?raw'
import search from 'lucide-static/icons/search.svg?raw'
import check from 'lucide-static/icons/check.svg?raw'
import info from 'lucide-static/icons/info.svg?raw'
import book from 'lucide-static/icons/book-open.svg?raw'

const escape = (s: string) => s.replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]!))
const codeBlocks = new Map<string, string>()
const revision = __RIFT_REVISION__
const versionLink = revision.hash ? 'https://github.com/Naymmmm/riftui/commit/' + revision.hash : 'https://github.com/Naymmmm/riftui'
let currentSlug = ''
let selectedTheme = 'Graphite'
let tocObserver: IntersectionObserver | undefined
let live = false
const root = document.getElementById('docs')!
root.innerHTML = '<a class="skip-link" href="#main-content">Skip to content</a>' +
  '<header class="masthead"><a class="brand" href="#introduction"><img src="/favicon.svg" alt="" width="27" height="27"><strong>RiftUI</strong><span class="brand-rule"></span><span>Docs</span></a><a class="version" href="' + versionLink + '" target="_blank" rel="noreferrer" title="' + (revision.dirty ? 'Local changes based on ' : 'Commit ') + escape(revision.hash || 'source archive') + '">' + escape(revision.version) + '</a>' +
  '<div class="head-links"><a href="https://github.com/Naymmmm/riftui" target="_blank" rel="noreferrer" class="repo-link" aria-label="RiftUI on GitHub">' + github + '</a><a class="sim-link" href="/simulator">Open simulator ' + external + '</a><button id="mobile-menu" class="icon-button" aria-label="Open documentation navigation" aria-expanded="false" aria-controls="sidebar">' + icon('menu') + '</button></div></header>' +
  '<aside class="sidebar" id="sidebar"><div class="search-wrap">' + search + '<input id="search" type="search" placeholder="Find a page…" aria-label="Search documentation" autocomplete="off"><kbd>⌘ K</kbd></div><nav id="navigation" aria-label="Documentation"></nav><div class="sidebar-foot">' + book + '<span>Built with the same library<br>you’re reading about.</span></div></aside>' +
  '<div class="mobile-shade" id="mobile-shade"></div><main id="main-content" tabindex="-1"><div class="reading-layout"><article id="article"></article><aside class="page-toc" aria-label="On this page"><span>On this page</span><nav id="toc"></nav></aside></div></main><div class="announce sr-only" role="status" aria-live="polite"></div>'

const navigation = document.getElementById('navigation')!
const article = document.getElementById('article')!
const searchInput = document.getElementById('search') as HTMLInputElement
const menu = document.getElementById('mobile-menu')!
const sidebar = document.getElementById('sidebar')!
const mobileBreakpoint = matchMedia('(max-width: 760px)')
function syncNavigation() {
  const closed = mobileBreakpoint.matches && !document.body.classList.contains('menu-open')
  sidebar.inert = closed
  sidebar.setAttribute('aria-hidden', String(closed))
}
mobileBreakpoint.addEventListener('change', () => {
  if (mobileBreakpoint.matches && !document.body.classList.contains('menu-open') && sidebar.contains(document.activeElement)) menu.focus({ preventScroll: true })
  syncNavigation()
})
function renderNavigation(query = '') {
  const needle = query.trim().toLowerCase()
  const matching = pages.filter(p => (p.title + ' ' + p.summary + ' ' + p.sections.map(s => s.title + ' ' + (s.text || []).join(' ') + ' ' + (s.code || '') + ' ' + (s.rows || []).flat().join(' ')).join(' ')).toLowerCase().includes(needle))
  navigation.innerHTML = groups.map(group => {
    const items = matching.filter(p => p.group === group)
    if (!items.length) return ''
    return '<div class="nav-group"><h2>' + group + '</h2>' + items.map(p => '<a href="#' + p.slug + '"' + (p.slug === currentSlug ? ' aria-current="page"' : '') + '>' + escape(p.navTitle || p.title) + (p.slug === 'themes' ? '<span class="nav-dot" aria-hidden="true"></span>' : '') + '</a>').join('') + '</div>'
  }).join('') || '<div class="no-results"><p>No pages found for “' + escape(query) + '”.</p><button id="clear-search">Clear search</button></div>'
  document.getElementById('clear-search')?.addEventListener('click', () => { searchInput.value = ''; renderNavigation(); searchInput.focus() })
}
function highlight(source: string) {
  const pattern = /(--[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b(?:local|function|end|if|then|else|elseif|for|in|do|return|true|false|nil|and|or|not)\b|\b\d+(?:\.\d+)?\b)/g
  let out = '', last = 0
  for (const match of source.matchAll(pattern)) {
    const t = match[0], i = match.index!
    const kind = t.startsWith('--') ? 'comment' : /^["']/.test(t) ? 'string' : /^\d/.test(t) ? 'number' : 'keyword'
    out += escape(source.slice(last, i)) + '<span class="syntax-' + kind + '">' + escape(t) + '</span>'
    last = i + t.length
  }
  return out + escape(source.slice(last))
}
function code(source: string, id: string, shell = false) {
  codeBlocks.set(id, source)
  return '<div class="code-block"><div class="code-head"><span>' + (shell ? 'Terminal' : 'Luau') + '</span><button class="copy-button" data-copy="' + id + '" aria-label="Copy ' + (shell ? 'terminal commands' : 'Luau example') + '">' + icon('copy') + '<span>Copy</span></button></div><pre id="code-' + id + '" tabindex="0"><code>' + highlight(source) + '</code></pre></div>'
}
function section(s: DocSection, page: DocPage) {
  let html = '<section class="doc-section" id="' + s.id + '"><h2><a href="#' + page.slug + '/' + s.id + '">' + escape(s.title) + '</a></h2>'
  html += (s.text || []).map(t => '<p>' + t + '</p>').join('')
  if (s.code) html += code(s.code, page.slug + '-' + s.id, page.slug === 'installation' && s.id === 'local')
  if (s.rows) html += '<div class="table-scroll" tabindex="0" role="region" aria-label="' + escape(s.title) + '"><table><thead><tr>' + s.columns!.map(c => '<th scope="col">' + escape(c) + '</th>').join('') + '</tr></thead><tbody>' + s.rows.map(row => '<tr>' + row.map((c, i) => '<' + (i === 0 ? 'th scope="row"' : 'td') + '>' + escape(c) + '</' + (i === 0 ? 'th' : 'td') + '>').join('') + '</tr>').join('') + '</tbody></table></div>'
  if (s.note) html += '<aside class="note">' + info + '<p>' + s.note + '</p></aside>'
  if (page.slug === 'button' && s.id === 'behavior') html += '<figure class="state-image"><a href="/docs/images/button-clicked.webp" target="_blank" rel="noreferrer"><img src="/docs/images/button-clicked.webp" alt="The actual RiftUI button example after one click: its label reads Callback ran 1 time and the output reads Button callback: 1." loading="lazy" width="660" height="500"></a><figcaption>After one click: your callback updates the label and prints its result.</figcaption></figure>'
  return html + '</section>'
}
function preview(page: DocPage) {
  return '<section class="example" aria-label="' + escape(page.title) + ' example"><div class="example-bar"><div role="tablist" aria-label="Example view"><button role="tab" id="screenshot-tab" aria-controls="example-view" aria-selected="true" data-view="screenshot">Screenshot</button><button role="tab" id="live-tab" tabindex="-1" aria-controls="example-view" aria-selected="false" data-view="live">' + icon('play') + 'Try it live</button></div><button id="replay" class="icon-button" aria-label="Restart live example" title="Restart example" hidden>' + icon('reset') + '</button><span class="example-origin">Rendered by RiftUI</span></div><div id="example-view" role="tabpanel" aria-labelledby="screenshot-tab"><a class="preview-image-link" href="/docs/images/' + page.demo + '.webp" target="_blank" rel="noreferrer"><img class="preview-image" src="/docs/images/' + page.demo + '.webp" width="660" height="500" alt="' + escape(page.title) + ': actual RiftUI interface rendered from the documentation example. Open for a full-size image."></a></div></section><p class="example-hint">' + escape(page.hint || 'Switch to Try it live to interact with this example. Output appears below the controls.') + '</p>'
}
function themeGallery() {
  const subtitles: Record<string, string> = { Graphite: 'Neutral near-black', Ink: 'True black', Slate: 'Cool blue-grey', Ember: 'Warm charcoal' }
  return '<div class="theme-gallery" role="group" aria-label="Theme screenshots">' + themes.map(t => '<button data-theme="' + t + '" aria-pressed="' + (t === selectedTheme) + '"><span class="theme-image"><img src="/docs/images/theme-' + t.toLowerCase() + '.webp" alt="' + t + ' theme preview" width="660" height="500" loading="lazy"></span><span class="theme-name"><span class="theme-swatch swatch-' + t.toLowerCase() + '"></span>' + t + '<span class="theme-check">' + check + '</span></span><small>' + subtitles[t] + '</small></button>').join('') + '</div>'
}
function render(page: DocPage) {
  codeBlocks.clear()
  live = false
  selectedTheme = 'Graphite'
  currentSlug = page.slug
  document.title = page.title + ' — RiftUI docs'
  article.innerHTML = '<div class="breadcrumb"><span>' + page.group + '</span>' + icon('chevron') + '<span>' + escape(page.title) + '</span></div><h1>' + escape(page.title) + '</h1><p class="lead">' + escape(page.summary) + '</p>' +
    (page.slug === 'introduction' ? '<figure class="intro-banner"><img src="/brand/riftui-banner.webp" alt="RiftUI" width="1280" height="640"></figure>' : '') + (page.demo ? preview(page) : '') + (page.slug === 'themes' ? themeGallery() : '') +
    page.sections.map(s => section(s, page)).join('') +
    '<footer class="article-footer"><a class="source-link" href="https://github.com/Naymmmm/riftui/blob/main/lib/RiftUI.luau" target="_blank" rel="noreferrer">Read the source ' + external + '</a><div class="page-turns">' + (() => {
      const i = pages.indexOf(page)
      return (i > 0 ? '<a href="#' + pages[i - 1].slug + '"><small>Previous</small><span>← ' + escape(pages[i - 1].title) + '</span></a>' : '<span></span>') + (i < pages.length - 1 ? '<a href="#' + pages[i + 1].slug + '"><small>Next</small><span>' + escape(pages[i + 1].title) + ' →</span></a>' : '')
    })() + '</div><p>RiftUI · Roblox UI library</p></footer>'
  document.getElementById('toc')!.innerHTML = (page.demo ? '<a href="#' + page.slug + '/example-view">Example</a>' : '') + page.sections.map(s => '<a href="#' + page.slug + '/' + s.id + '">' + escape(s.title) + '</a>').join('')
  renderNavigation(searchInput.value)
  bindPage(page)
  tocObserver?.disconnect()
  tocObserver = new IntersectionObserver(entries => {
    const hit = entries.find(e => e.isIntersecting)
    if (!hit) return
    document.querySelectorAll('#toc a').forEach(a => a.classList.toggle('active', a.getAttribute('href') === '#' + page.slug + '/' + hit.target.id))
  }, { rootMargin: '-80px 0px -65% 0px' })
  article.querySelectorAll('.doc-section').forEach(s => tocObserver!.observe(s))
}
function bindPage(page: DocPage) {
  article.querySelectorAll<HTMLButtonElement>('[data-copy]').forEach(b => b.addEventListener('click', async () => {
    const value = codeBlocks.get(b.dataset.copy!)!
    try {
      await navigator.clipboard.writeText(value)
      b.innerHTML = check + '<span>Copied</span>'
      document.querySelector('.announce')!.textContent = 'Code copied to clipboard.'
      setTimeout(() => { if (b.isConnected) b.innerHTML = icon('copy') + '<span>Copy</span>' }, 1800)
    } catch {
      const range = document.createRange()
      range.selectNodeContents(document.getElementById('code-' + b.dataset.copy)!)
      getSelection()?.removeAllRanges(); getSelection()?.addRange(range)
      document.querySelector('.announce')!.textContent = 'Clipboard is unavailable. Code selected; copy it using your keyboard.'
    }
  }))
  article.querySelectorAll<HTMLButtonElement>('[data-view]').forEach(b => b.addEventListener('click', () => {
    live = b.dataset.view === 'live'
    article.querySelectorAll<HTMLButtonElement>('[data-view]').forEach(t => { t.setAttribute('aria-selected', String(t === b)); t.tabIndex = t === b ? 0 : -1 })
    const view = document.getElementById('example-view')!
    view.setAttribute('aria-labelledby', b.id)
    view.innerHTML = live ? '<iframe id="live-example" title="' + escape(page.title) + ' — interactive Luau example" src="/docs/preview.html?demo=' + page.demo + '&theme=' + selectedTheme + '" allow="clipboard-write"></iframe>' : '<a class="preview-image-link" href="' + imagePath(page) + '" target="_blank" rel="noreferrer"><img class="preview-image" src="' + imagePath(page) + '" alt="' + escape(page.title) + ' rendered example" width="660" height="500"></a>'
    document.getElementById('replay')!.hidden = !live
  }))
  article.querySelectorAll<HTMLButtonElement>('[data-theme]').forEach(b => b.addEventListener('click', () => {
    selectedTheme = b.dataset.theme!
    article.querySelectorAll<HTMLButtonElement>('[data-theme]').forEach(t => t.setAttribute('aria-pressed', String(t === b)))
    if (live) (document.getElementById('live-example') as HTMLIFrameElement)?.contentWindow?.postMessage({ type: 'rift-docs-theme', theme: selectedTheme }, location.origin)
    else {
      const img = document.querySelector<HTMLImageElement>('.preview-image')!
      img.src = imagePath(page); img.alt = selectedTheme + ' palette applied to the actual RiftUI theme example'
      img.parentElement!.setAttribute('href', img.src)
    }
  }))
  document.getElementById('replay')?.addEventListener('click', () => (document.getElementById('live-example') as HTMLIFrameElement)?.contentWindow?.postMessage({ type: 'rift-docs-replay' }, location.origin))
  const tabs = [...article.querySelectorAll<HTMLButtonElement>('[data-view]')]
  tabs.forEach((tab, i) => tab.addEventListener('keydown', e => {
    if (e.key === 'ArrowLeft' || e.key === 'ArrowRight') { e.preventDefault(); const next = tabs[(i + 1) % tabs.length]; next.focus(); next.click() }
  }))
}
function imagePath(page: DocPage) { return '/docs/images/' + (page.slug === 'themes' ? 'theme-' + selectedTheme.toLowerCase() : page.demo) + '.webp' }
function closeMenu() {
  if (mobileBreakpoint.matches && sidebar.contains(document.activeElement)) menu.focus({ preventScroll: true })
  document.body.classList.remove('menu-open'); menu.setAttribute('aria-expanded', 'false'); syncNavigation()
}
function route() {
  const [slug = '', anchor] = location.hash.slice(1).split('/')
  const page = getPage(slug || 'introduction')
  if (!page) {
    currentSlug = ''
    article.innerHTML = '<h1>Page not found</h1><p class="lead">This documentation link does not match a page.</p><p><a href="#introduction">Return to Introduction →</a></p>'
    document.getElementById('toc')!.innerHTML = ''
    renderNavigation(searchInput.value)
    return
  }
  const changed = currentSlug !== page.slug
  if (changed) render(page)
  closeMenu()
  if (anchor) document.getElementById(anchor)?.scrollIntoView({ block: 'start' })
  else if (changed) { window.scrollTo(0, 0); if (document.activeElement !== document.body) document.getElementById('main-content')!.focus({ preventScroll: true }) }
}
document.querySelector('.skip-link')!.addEventListener('click', e => { e.preventDefault(); document.getElementById('main-content')!.focus(); window.scrollTo(0, 0) })
searchInput.addEventListener('input', () => renderNavigation(searchInput.value))
menu.addEventListener('click', () => { const open = document.body.classList.toggle('menu-open'); menu.setAttribute('aria-expanded', String(open)); syncNavigation() })
document.getElementById('mobile-shade')!.addEventListener('click', closeMenu)
window.addEventListener('keydown', e => {
  if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); document.body.classList.add('menu-open'); menu.setAttribute('aria-expanded', 'true'); syncNavigation(); searchInput.focus() }
  if (e.key === 'Escape') { const wasOpen = document.body.classList.contains('menu-open'); closeMenu(); if (wasOpen && matchMedia('(max-width: 760px)').matches) menu.focus(); else if (document.activeElement === searchInput) searchInput.blur() }
})
window.addEventListener('hashchange', route)
syncNavigation()
route()
