<script lang="ts">
  import { onMount } from 'svelte'
  import {
    detectFileSystem,
    VaultIndex,
    type FileSystem,
    type FileEntry,
    type IndexedNote,
    type Backlink,
  } from '@nmy/core'
  import Editor from './lib/Editor.svelte'
  import FolderTree from './lib/FolderTree.svelte'
  import BacklinksPanel from './lib/BacklinksPanel.svelte'
  import CommandPalette, { type PaletteItem } from './lib/CommandPalette.svelte'
  import { applyTheme, cycleTheme, loadTheme, type ThemePreference } from './lib/theme.js'

  let fs: FileSystem | null = $state(null)
  let mode: string = $state('detecting…')
  let rootEntries: FileEntry[] = $state([])
  let error: string | null = $state(null)

  const index = new VaultIndex()
  let indexVersion: number = $state(0)

  let activePath: string | null = $state(null)
  let activeDoc: string = $state('')
  let backlinks: Backlink[] = $state([])

  let pendingContent: string | null = null
  let saveTimer: ReturnType<typeof setTimeout> | undefined
  let saveStatus: 'idle' | 'dirty' | 'saving' | 'saved' = $state('idle')

  let paletteMode: 'closed' | 'switcher' | 'commands' = $state('closed')
  let sidebarOpen: boolean = $state(true)
  let theme: ThemePreference = $state('system')

  onMount(async () => {
    theme = loadTheme()
    applyTheme(theme)
    try {
      const detected = await detectFileSystem()
      fs = detected.fs
      mode = detected.mode
      await refreshTree()
      await index.rebuild(fs)
      indexVersion++
    } catch (e) {
      error = e instanceof Error ? e.message : String(e)
    }
  })

  async function refreshTree() {
    if (!fs) return
    rootEntries = await fs.list('/')
  }

  $effect(() => {
    void indexVersion
    backlinks = activePath ? index.getBacklinks(activePath) : []
  })

  async function createNote(initialPath?: string) {
    if (!fs) return
    let raw: string | null | undefined = initialPath
    if (!raw) raw = window.prompt('new note name (folder/name allowed)', 'untitled')
    if (!raw) return
    const name = raw.endsWith('.md') ? raw : `${raw}.md`
    const path = name.startsWith('/') ? name : `/${name}`
    if (await fs.exists(path)) {
      error = `${path} already exists`
      return
    }
    const title = path.split('/').pop()!.replace(/\.md$/, '')
    const content = `# ${title}\n\n`
    await fs.write(path, content)
    index.upsertFromContent(path, content)
    indexVersion++
    await refreshTree()
    await openFile(path)
  }

  async function createFolder() {
    if (!fs) return
    const name = window.prompt('new folder name', '')?.trim()
    if (!name) return
    const path = name.startsWith('/') ? name : `/${name}`
    await fs.mkdir(path)
    await refreshTree()
  }

  async function openFile(path: string) {
    if (!fs || path === activePath) return
    await flushSave()
    try {
      activeDoc = await fs.read(path)
      activePath = path
      saveStatus = 'idle'
    } catch (e) {
      error = `cannot open ${path}: ${e instanceof Error ? e.message : String(e)}`
    }
  }

  function handleEdit(content: string) {
    if (!activePath || !fs) return
    pendingContent = content
    saveStatus = 'dirty'
    if (saveTimer) clearTimeout(saveTimer)
    saveTimer = setTimeout(flushSave, 500)
  }

  async function flushSave() {
    if (saveTimer) {
      clearTimeout(saveTimer)
      saveTimer = undefined
    }
    if (pendingContent === null || !activePath || !fs) return
    const content = pendingContent
    pendingContent = null
    saveStatus = 'saving'
    await fs.write(activePath, content)
    index.upsertFromContent(activePath, content)
    indexVersion++
    saveStatus = 'saved'
  }

  async function handleOpenLink(target: string) {
    const resolved = index.resolveLink(target)
    if (resolved) {
      await openFile(resolved.path)
      return
    }
    if (!fs) return
    const path = target.includes('/')
      ? (target.endsWith('.md') ? `/${target}` : `/${target}.md`)
      : `/${target}.md`
    const content = `# ${target}\n\n`
    await fs.write(path, content)
    index.upsertFromContent(path, content)
    indexVersion++
    await refreshTree()
    await openFile(path)
  }

  function resolveLink(target: string): boolean {
    void indexVersion
    return index.resolveLink(target) !== null
  }

  function searchNotes(query: string): IndexedNote[] {
    void indexVersion
    return index.searchTitles(query, 12)
  }

  function statusLabel(s: typeof saveStatus): string {
    return s === 'saving' ? 'saving…' : s === 'dirty' ? 'unsaved' : s === 'saved' ? 'saved' : ''
  }

  function setTheme(next: ThemePreference) {
    theme = next
    applyTheme(next)
  }

  function toggleSidebar() {
    sidebarOpen = !sidebarOpen
  }

  function isMod(e: KeyboardEvent): boolean {
    return e.metaKey || e.ctrlKey
  }

  function onGlobalKeydown(e: KeyboardEvent) {
    if (paletteMode !== 'closed') return // palette has its own keymap

    if (isMod(e) && !e.shiftKey && !e.altKey && e.key.toLowerCase() === 'o') {
      e.preventDefault()
      paletteMode = 'switcher'
      return
    }
    if (isMod(e) && !e.altKey && (e.key.toLowerCase() === 'k' || (e.shiftKey && e.key.toLowerCase() === 'p'))) {
      e.preventDefault()
      paletteMode = 'commands'
      return
    }
    if (isMod(e) && e.shiftKey && e.key.toLowerCase() === 'n') {
      e.preventDefault()
      createNote()
      return
    }
    if (isMod(e) && !e.shiftKey && e.key === '\\') {
      e.preventDefault()
      toggleSidebar()
      return
    }
  }

  // Items shown by the quick switcher (Cmd+O)
  const switcherItems = $derived.by<PaletteItem[]>(() => {
    void indexVersion
    return index.all().map((note) => ({
      id: note.path,
      label: note.title,
      hint: note.path.replace(/^\//, '').replace(/\.md$/i, ''),
    }))
  })

  // Items shown by the command palette (Cmd+K)
  const commandItems = $derived.by<PaletteItem[]>(() => [
    {
      id: 'cmd:new-note',
      label: 'New note',
      group: 'note',
      hint: '⌘⇧N',
    },
    {
      id: 'cmd:new-folder',
      label: 'New folder',
      group: 'note',
    },
    {
      id: 'cmd:switcher',
      label: 'Open quick switcher',
      group: 'go',
      hint: '⌘O',
    },
    {
      id: 'cmd:toggle-sidebar',
      label: sidebarOpen ? 'Hide sidebar' : 'Show sidebar',
      group: 'view',
      hint: '⌘\\',
    },
    {
      id: 'cmd:theme-system',
      label: 'Theme: follow system',
      group: 'view',
      disabled: theme === 'system',
    },
    {
      id: 'cmd:theme-light',
      label: 'Theme: light',
      group: 'view',
      disabled: theme === 'light',
    },
    {
      id: 'cmd:theme-dark',
      label: 'Theme: dark',
      group: 'view',
      disabled: theme === 'dark',
    },
    {
      id: 'cmd:cycle-theme',
      label: `Cycle theme (now: ${theme})`,
      group: 'view',
    },
  ])

  function handlePaletteSelect(item: PaletteItem) {
    const mode = paletteMode
    paletteMode = 'closed'
    if (mode === 'switcher') {
      void openFile(item.id)
      return
    }
    switch (item.id) {
      case 'cmd:new-note':
        void createNote()
        break
      case 'cmd:new-folder':
        void createFolder()
        break
      case 'cmd:switcher':
        paletteMode = 'switcher'
        break
      case 'cmd:toggle-sidebar':
        toggleSidebar()
        break
      case 'cmd:theme-system':
        setTheme('system')
        break
      case 'cmd:theme-light':
        setTheme('light')
        break
      case 'cmd:theme-dark':
        setTheme('dark')
        break
      case 'cmd:cycle-theme':
        setTheme(cycleTheme(theme))
        break
    }
  }
</script>

<svelte:window onkeydown={onGlobalKeydown} />

<main class:sidebar-closed={!sidebarOpen}>
  <aside class="sidebar">
    <header>
      <h1>nmy</h1>
      <small>{mode}</small>
    </header>

    <div class="actions">
      <button onclick={() => createNote()} disabled={!fs}>+ note</button>
      <button onclick={createFolder} disabled={!fs}>+ folder</button>
    </div>

    {#if fs}
      <FolderTree entries={rootEntries} {fs} {activePath} onOpen={openFile} />
    {/if}

    {#if rootEntries.length === 0 && !error}
      <p class="empty">no notes yet</p>
    {/if}

    {#if error}
      <p class="error">{error}</p>
    {/if}

    <footer>
      <button class="kbd-hint" onclick={() => (paletteMode = 'commands')}>
        ⌘K commands
      </button>
    </footer>
  </aside>

  <section class="main-pane">
    {#if activePath}
      <div class="editor-header">
        <span class="path">{activePath.replace(/^\//, '')}</span>
        <span class="status" data-status={saveStatus}>{statusLabel(saveStatus)}</span>
      </div>
      <div class="editor-body">
        {#key activePath}
          <Editor
            initialDoc={activeDoc}
            onChange={handleEdit}
            onOpenLink={handleOpenLink}
            {resolveLink}
            {searchNotes}
          />
        {/key}
      </div>
      <BacklinksPanel {backlinks} onOpen={openFile} />
    {:else}
      <div class="placeholder">
        <p>select or create a note</p>
        <p class="hint">files live in {mode === 'opfs' ? 'browser storage' : 'your folder'}</p>
        <p class="hint">
          press <kbd>⌘O</kbd> to switch notes · <kbd>⌘K</kbd> for commands · <kbd>⌘⇧N</kbd> for new note
        </p>
      </div>
    {/if}
  </section>
</main>

<CommandPalette
  open={paletteMode === 'switcher'}
  placeholder="Open note…"
  items={switcherItems}
  onSelect={handlePaletteSelect}
  onClose={() => (paletteMode = 'closed')}
/>

<CommandPalette
  open={paletteMode === 'commands'}
  placeholder="Run a command…"
  items={commandItems}
  onSelect={handlePaletteSelect}
  onClose={() => (paletteMode = 'closed')}
/>

<style>
  main {
    display: grid;
    grid-template-columns: 260px 1fr;
    height: 100%;
    transition: grid-template-columns 0.18s ease;
  }

  main.sidebar-closed {
    grid-template-columns: 0 1fr;
  }

  main.sidebar-closed .sidebar {
    overflow: hidden;
    padding-left: 0;
    padding-right: 0;
    border-right: none;
  }

  .sidebar {
    background: var(--sidebar);
    border-right: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    padding: 12px;
    gap: 12px;
    overflow: auto;
    min-width: 0;
  }

  header {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
  }

  h1 {
    margin: 0;
    font-size: 18px;
    font-weight: 600;
    letter-spacing: -0.01em;
  }

  small {
    color: var(--fg-muted);
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .actions {
    display: flex;
    gap: 6px;
  }

  .empty {
    color: var(--fg-muted);
    padding: 4px 8px;
    font-size: 13px;
  }

  .error {
    color: var(--error);
    font-size: 12px;
    margin: 0;
  }

  footer {
    margin-top: auto;
    padding-top: 12px;
    border-top: 1px solid var(--border);
  }

  .kbd-hint {
    width: 100%;
    text-align: left;
    color: var(--fg-muted);
    font-size: 11px;
    background: transparent;
    border: none;
    border-radius: 4px;
    padding: 4px 8px;
    cursor: pointer;
  }

  .kbd-hint:hover {
    background: var(--hover);
    color: var(--fg);
  }

  .main-pane {
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .editor-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 10px 18px;
    border-bottom: 1px solid var(--border);
    font-size: 12px;
    color: var(--fg-muted);
    flex-shrink: 0;
  }

  .path {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  }

  .status {
    min-width: 60px;
    text-align: right;
    transition: opacity 0.2s;
  }

  .status[data-status='idle'] {
    opacity: 0;
  }

  .editor-body {
    flex: 1;
    overflow: hidden;
    min-height: 0;
  }

  .placeholder {
    flex: 1;
    display: grid;
    place-content: center;
    color: var(--fg-muted);
    gap: 8px;
    text-align: center;
    padding: 16px;
  }

  .placeholder p {
    margin: 0;
  }

  .hint {
    font-size: 12px;
    opacity: 0.8;
  }

  kbd {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    background: var(--code-bg);
    border: 1px solid var(--border);
    border-radius: 4px;
    padding: 1px 6px;
    font-size: 11px;
  }
</style>
