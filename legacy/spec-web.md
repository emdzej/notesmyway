# nmy — Notes My Way

**Status:** living document. Last updated 2026-06-17.
**One-line:** a local-first, plain-markdown notes app with half-WYSIWYG editing, wikilinks, and a plugin system — web first, desktop later.

---

## 1. Vision

nmy is a personal knowledge base built around three non-negotiables:

1. **Your notes are plain `.md` files in plain folders.** Not a sidecar database, not a custom binary, not a virtual filesystem. Anything you can do with nmy, you can also do with `vim`, `grep`, and `git`.
2. **The editor stays out of the way.** Half-WYSIWYG (Medium/Confluence-style): `# Hello` renders styled while the source remains visible and editable. The text on disk is what you typed.
3. **It runs anywhere modern web runs.** Browser PWA first (works on iOS Safari without the App Store), then Tauri desktop using the same TypeScript codebase.

If a feature compromises any of those three, it doesn't ship.

---

## 2. Goals and non-goals

### Goals
- **Local-first.** All notes stored on the user's device. Online is opt-in for sync only.
- **Format fidelity.** Editor reads and writes the same bytes — no lossy round-trips.
- **Speed.** Cold start under a second on a mid-range machine. Typing latency indistinguishable from a native text editor.
- **Cross-platform via one codebase.** Web (PWA) → Tauri (desktop) → mobile (PWA). One core, multiple shells.
- **Extensible.** Plugins can add renderers (e.g. Mermaid), commands, side panels.
- **Keyboard-first UX.** Every action reachable via shortcut or command palette.
- **Clean visual design.** Light + dark theme, system-aware, distraction-free.

### Non-goals (for now)
- **Multi-user real-time collaboration.** Single-user only. Re-evaluate when there is a concrete request.
- **Server-side rendering / SSR.** Pure client app. Sync may use a server; the editor never depends on one.
- **Database-backed notes.** No SQLite-as-storage; SQLite is allowed as an _index_, never as the source of truth.
- **AI / LLM features in v1.** Plugin territory if it ships, not core.
- **Mobile-native apps.** iOS/Android via PWA. No App Store presence (no $99/yr Apple developer fee).

---

## 3. Users and scenarios

Single user: a developer-leaning knowledge worker who:
- already lives in markdown (Obsidian, Notion, Bear, plain `.md` in a folder)
- wants the data portable to whatever comes next
- types fast and uses keyboard shortcuts
- works across at least two devices

Primary scenarios:
1. **Capture an idea** — `Cmd+N` → type → autosaves while you write.
2. **Link as you think** — type `[[`, fuzzy-pick an existing note, continue writing.
3. **Find later** — open command palette, type, results across titles + content.
4. **Read on phone** — same vault on iPhone via PWA, edits sync back.
5. **Move on** — export the whole vault as a folder of `.md` files at any moment.

---

## 4. Functional requirements

### 4.1 Notes and folders
- Notes are `.md` files with UTF-8 content. Optional YAML frontmatter for metadata (tags, aliases, created/modified).
- Folders are real folders on the storage backend. Nesting is unlimited.
- File names use the conventional rules of the host filesystem (case-sensitive on disk; nmy normalizes only for matching).
- Hidden files / dotfiles are listed but de-emphasized.

### 4.2 Editor
- **Source-of-truth = text.** What's on screen is what's on disk (modulo decorations).
- **Half-WYSIWYG live preview.** Headings render at heading size, **bold** renders bold, code blocks get syntax highlighting — markers (`#`, `**`, ` ``` `) remain visible.
- **GitHub-flavored markdown** as the baseline: tables, task lists, strikethrough, fenced code with language tags, footnotes.
- **Math:** `$inline$` and `$$block$$` rendered via KaTeX (plugin or built-in TBD).
- **Code blocks:** syntax-highlighted via CM6's nested language support (~50 languages, lazy-loaded). `Cmd+Shift+F` formats the block (plugin via Prettier-WASM).
- **Wikilinks:** `[[note title]]` resolves to a note by name; `[[note|alias]]` supports display text; auto-complete on `[[`.
- **Embeds (later):** `![[image.png]]` for attachments, `![[other-note]]` for transclusion.
- **Mermaid, KaTeX, custom blocks:** rendered via plugins using widget decorations.

### 4.3 Navigation
- **Sidebar:** file tree, expandable folders, drag-to-move (later).
- **Command palette** (`Cmd+P` or `Cmd+K`): open note, run command, search content.
- **Quick switcher** (`Cmd+O`): fuzzy-find by title.
- **Backlinks panel:** for the current note, show every other note that links to it.
- **Outline panel:** headings of the current note as a jump list.

### 4.4 Search and indexing
- **Full-text search** across all notes.
- **Tag search** (`#tag` syntax and YAML frontmatter `tags:`).
- **Title search** (fastest path).
- Index backed by SQLite (via `sqlite-wasm` in browser, native in Tauri) + FTS5.
- Index is rebuildable from the files on disk. Losing the index is never data loss.

### 4.5 Sync
**v1: no built-in sync.** Two escape hatches:
- **Export to folder** via File System Access API on Chromium → user syncs the folder via iCloud Drive, Dropbox, Syncthing, etc.
- **Export as `.zip`** on browsers without FSA (iOS Safari, Firefox).

**Future options under consideration** (will pick one; not stacked):
- File-level sync via a Git provider (isomorphic-git, repo per vault).
- File-level sync via a generic cloud (Dropbox / Google Drive / WebDAV).
- CRDT-based real-time sync (Y.js or Automerge) — only if multi-device live editing becomes a hard requirement.

### 4.6 Plugins
- Sandboxed via `iframe` + `comlink` postMessage bridge. Plugins cannot touch the host DOM directly.
- Plugin API surface (typed):
  - **Renderers:** transform a markdown node into HTML/SVG (Mermaid, KaTeX, custom code-block langs).
  - **Commands:** add entries to the command palette.
  - **Side panels:** mount a view in the sidebar or bottom dock.
  - **Settings:** declare schema; nmy renders the settings UI.
- Distribution: TBD. Likely a manifest file referencing an ES module URL; install via a "from URL" dialog.
- First-party plugins to ship: Mermaid, KaTeX, Prettier-for-code-blocks.

### 4.7 Theming and accessibility
- **Light + dark theme**, follows OS preference by default. Manual override via settings (`[data-theme="light"|"dark"]`).
- All colors via CSS variables defined with `light-dark()` so theme switching is variable-only — no JS, no flash.
- Respect `prefers-reduced-motion`.
- Keyboard navigation reaches every action.

### 4.8 Keyboard shortcuts (initial set)
| Action | Shortcut | Status |
|---|---|---|
| New note | `Cmd+Shift+N` | ✅ M3 |
| Open quick switcher | `Cmd+O` | ✅ M3 |
| Command palette | `Cmd+K` / `Cmd+Shift+P` | ✅ M3 |
| Toggle sidebar | `Cmd+\` | ✅ M3 |
| Follow wikilink | `Cmd/Ctrl+click` | ✅ M2 |
| Save (manual) | `Cmd+S` (debounced autosave makes this rare) | ◻️ |
| Format code block | `Cmd+Shift+F` | ◻️ M5 |
| Next/prev note in history | `Cmd+]` / `Cmd+[` | ◻️ |

All shortcuts user-customizable (later).

**Note on browser-reserved keys.** `Cmd+N` opens a new browser window in every desktop browser — `preventDefault()` cannot intercept it. nmy uses `Cmd+Shift+N` instead. Similarly `Cmd+T`, `Cmd+W`, `Cmd+Q` are off-limits and won't be bound.

---

## 5. Architecture

### 5.1 Repository layout (monorepo)

```
nmy/
├── apps/
│   ├── web/                   Svelte 5 + Vite 8 + TS PWA. Primary target.
│   └── desktop/               (later) Tauri 2 shell wrapping the web build.
├── packages/
│   ├── core/                  FileSystem interface, plugin API types, capability detection.
│   ├── editor/                (extracts from apps/web once apps/desktop materializes) CM6 extensions, themes, markdown highlighting.
│   ├── plugin-mermaid/        (later) reference plugin.
│   └── plugin-katex/          (later)
├── pnpm-workspace.yaml        Workspaces + version catalog.
├── turbo.json                 Task graph (build / dev / check / lint / clean).
├── tsconfig.base.json         Strict TS, bundler resolution, DOM.AsyncIterable.
└── spec.md                    This file.
```

Tooling: **pnpm 10** for installs, **Turborepo 2** for the task graph, **TypeScript 5.9** in strict mode with `verbatimModuleSyntax`.

### 5.2 Layer model

```
┌─────────────────────────────────────────────────────────┐
│  apps/web (Svelte 5 UI)                                 │
│  - file tree, command palette, settings, sidebars       │
└─────────────┬───────────────────────────────────────────┘
              │ uses
              ▼
┌─────────────────────────────────────────────────────────┐
│  packages/editor (CodeMirror 6 wrapper, later)          │
│  - markdown live-preview decorations                    │
│  - nested code block languages                          │
│  - wikilink autocomplete, slash commands                │
└─────────────┬───────────────────────────────────────────┘
              │ reads/writes via
              ▼
┌─────────────────────────────────────────────────────────┐
│  packages/core (FileSystem abstraction + plugin API)    │
│  - FileSystem interface                                 │
│  - OPFS / FSA / Tauri implementations                   │
│  - capability detection                                 │
│  - plugin runtime (iframe + comlink)                    │
└─────────────┬───────────────────────────────────────────┘
              │ backed by
              ▼
┌──────────────┬─────────────┬────────────────────────────┐
│  OPFS        │  FSA folder │  Tauri native FS (later)   │
└──────────────┴─────────────┴────────────────────────────┘
```

### 5.3 The `FileSystem` interface

The single most important abstraction. Defined in `packages/core/src/filesystem/types.ts`:

```ts
interface FileSystem {
  read(path: string): Promise<string>
  write(path: string, content: string): Promise<void>
  delete(path: string): Promise<void>
  list(path: string): Promise<FileEntry[]>
  exists(path: string): Promise<boolean>
  move(from: string, to: string): Promise<void>
  mkdir(path: string): Promise<void>
}
```

All paths are absolute, forward-slash, root `/`. Implementations:

| Backend | Trigger | Notes |
|---|---|---|
| **OPFS** | Default on web, no prompt | Browser sandbox. Files real `.md`, just not user-visible until exported. |
| **FSA** | User clicks "Open folder…" on Chromium | Real folder on disk. Directory handle persisted in IndexedDB across sessions. |
| **Tauri native** | Desktop app (later) | Direct OS filesystem via Rust `notify` crate. |

OPFS and FSA share `HandleFileSystem` (any `FileSystemDirectoryHandle`). Tauri will be a separate impl behind the same interface.

### 5.4 Storage strategy on the web

OPFS is a **location**, not a **format**. Files in OPFS are plain `.md` bytes inside a real folder hierarchy. The user can always:
1. **Export to a real folder** via FSA on Chromium (`writable.write` into a user-picked directory).
2. **Download as `.zip`** on browsers without FSA (iOS Safari, Firefox).
3. **Switch to FSA mode** at any time — the app then works directly against a user folder, no copy.

**Storage eviction on iOS.** Safari can clear OPFS after ~7 weeks of inactivity. Mitigation: prompt installation to Home Screen during onboarding — installed PWAs get persistent storage. Document this clearly in the onboarding flow.

### 5.5 Editor architecture

**Choice: CodeMirror 6** over ProseMirror / Lexical / Milkdown.

Why:
- **Text is the source of truth.** CM6 stores the document as a `Text` rope. Serialization is `doc.toString()`. ProseMirror stores a tree and serializes _to_ markdown — lossy in edge cases (custom HTML, comment placement, frontmatter ordering).
- **Nested languages are first-class.** `markdown({ codeLanguages: languages })` from `@codemirror/lang-markdown` + `@codemirror/language-data` syntax-highlights fenced code blocks for ~50 languages, lazy-loaded.
- **Live preview via decorations.** `Decoration.replace` and `Decoration.mark` give the Obsidian-style "rendered while editing" effect without changing the underlying text.
- **Performance.** CM6 was built for large documents (1M+ lines).
- **Proof.** Obsidian rewrote from CM5 to CM6 specifically to get live preview. Pattern is battle-tested.

Editor pipeline:

```
.md text on disk
   │
   ▼
EditorState (CM6 rope)
   │  parsed by @codemirror/lang-markdown (Lezer grammar)
   ▼
Syntax tree (nested into per-language trees inside code blocks)
   │  highlight via HighlightStyle bound to CSS variables
   ▼
Decoration set (mark for inline styles, widget for Mermaid/KaTeX/code-pills)
   │
   ▼
DOM
```

### 5.6 Plugin model

Plugins run in a sandboxed `<iframe>`. Communication via `comlink` (typed RPC over postMessage). The host exposes a versioned API; plugins declare their dependencies and capabilities in a manifest:

```json
{
  "name": "mermaid",
  "version": "1.0.0",
  "entry": "./dist/index.js",
  "capabilities": ["render"],
  "renders": ["mermaid"]
}
```

For a `render` capability registered for `mermaid` code blocks, the host calls `plugin.render(blockText)` and receives an SVG/HTML string + a content-hash key for caching. No direct DOM access from the plugin.

This trades some expressiveness vs. Obsidian's "plugins are full Node" model for a real security boundary — a malicious plugin cannot read other notes, exfiltrate, or attach event listeners.

---

## 6. Data model

### 6.1 File on disk
A note is a UTF-8 `.md` file with optional YAML frontmatter:

```markdown
---
title: My note            # optional; defaults to filename
aliases: [shortname]      # alternate names for wikilink resolution
tags: [project, idea]
created: 2026-06-16T10:00:00Z
updated: 2026-06-16T14:32:00Z
---

# My note

Body in [[CommonMark]] + GFM with extensions.
```

Frontmatter is **optional**. nmy never requires it.

### 6.2 Index (SQLite + FTS5)
Rebuilt from disk. Schema sketch:

```sql
CREATE TABLE notes (
  path TEXT PRIMARY KEY,        -- "/projects/foo.md"
  title TEXT,                   -- from frontmatter or first H1 or basename
  modified INTEGER,             -- mtime ms
  size INTEGER
);

CREATE TABLE links (
  src_path TEXT,                -- "/a.md"
  target TEXT,                  -- "b" (resolved later to "/b.md")
  display TEXT                  -- alias if [[b|display]]
);

CREATE TABLE tags (
  path TEXT,
  tag TEXT
);

CREATE VIRTUAL TABLE notes_fts USING fts5(
  path UNINDEXED,
  title,
  body,
  tokenize='porter unicode61'
);
```

Backlinks = `SELECT src_path FROM links WHERE target = ?`. Wikilink autocomplete = FTS on titles + alias table.

### 6.3 App state
Lives in memory, persisted to `localStorage` / IndexedDB:
- `activePath` — currently open note
- `history` — recent notes (for `Cmd+]/[`)
- `vault.kind` — `'opfs' | 'fsa' | 'native'`
- `vault.handle` — IndexedDB-persisted FSA `FileSystemDirectoryHandle` when applicable
- `settings` — theme override, keymap overrides, plugin enable list

No app state is required to read the notes. Nuking app state at most loses history and forces re-picking the FSA folder.

---

## 7. UI/UX principles

- **Distraction-free.** Default layout: sidebar + editor. Everything else (backlinks, outline, command palette) opens on demand.
- **Keyboard-first.** Every command palette entry is operable via keyboard. Mouse use is optional.
- **No modals if a panel will do.** Use slide-in sidebars; reserve modals for destructive confirms.
- **Status, not noise.** Save state ("unsaved / saving… / saved") shown subtly in the editor header, fades when idle.
- **Type, then look.** Markdown markers stay visible — the live preview is style, not hide. Power users see the source they wrote.
- **Mobile-first sidebar collapse.** Below 700px viewport: sidebar collapses behind a hamburger; editor takes the full width.

---

## 8. Roadmap

Each milestone is a working app. Ship value, then iterate.

### M0 — Scaffold ✅ (2026-06-15)
- pnpm + Turborepo monorepo
- apps/web with Svelte 5 + Vite 8 + TS
- packages/core with `FileSystem` interface + OPFS + FSA + capability detection
- Light/dark theme via `color-scheme: light dark` + `light-dark()` variables

### M1 — Editor + autosave ✅ (2026-06-16)
- CodeMirror 6 wrapped in `Editor.svelte`
- Markdown + nested code block languages (~50 langs)
- Heading size scaling + dimmed punctuation via custom `HighlightStyle`
- Click-to-open in file tree
- 500ms debounced autosave with `dirty / saving… / saved` status

### M2 — Linking and finding ✅ (2026-06-16)
- `[[` autocomplete (in-memory index over `fs.list` recursive crawl)
- Backlinks panel for the active note
- Folder support in the tree (expand/collapse, nested rendering)
- Wikilink decoration + Cmd/Ctrl-click navigation; broken-link auto-creation

### M3 — Power tools (partial; 2026-06-17)
- ✅ Command palette (`Cmd+K` / `Cmd+Shift+P`) — generic overlay reused for quick switcher
- ✅ Quick switcher (`Cmd+O`) — fuzzy on indexed titles
- ✅ Theme cycle (system / light / dark), persisted to localStorage
- ✅ Sidebar toggle (`Cmd+\`)
- ◻️ Full-text search backed by `sqlite-wasm` + FTS5
- ◻️ Outline panel (current note's headings)
- ◻️ Tag index + browser
- ◻️ Note history (`Cmd+]` / `Cmd+[`)

### M4 — Real folders + escape hatches
- "Open folder…" → switch to FSA mode, persist handle in IndexedDB
- "Export as zip" for non-FSA browsers
- File watcher (polling under FSA, native under Tauri later)
- Conflict UI when external edits land

### M5 — Plugins
- iframe + comlink runtime
- Manifest + install-from-URL
- Ship Mermaid + KaTeX as first-party plugins
- Settings UI rendered from plugin schema

### M6 — Live preview polish
- Hide markdown markers when cursor isn't on the line (Obsidian-style)
- Inline rendered images, transclusions (`![[other-note]]`)
- Slash commands (`/` opens insert menu)

### M7 — Desktop shell (Tauri)
- `apps/desktop` wrapping the web build
- Native `FileSystem` impl via Rust + `notify` watcher
- Multi-window support
- Tray icon + global quick-capture hotkey

### M8 — Sync (decision pending)
Pick one — file-level via Git, or cloud-folder, or CRDT. Decision criteria documented when reached.

---

## 9. Open questions

These are unresolved and will be re-opened when reached:

1. **Sync provider.** Git? Cloud folder? CRDT? Defer until M8.
2. **Plugin distribution.** Single npm-style registry? Install from URL? Curated catalog?
3. **Vault encryption.** Browser-side encryption at rest? Per-note password? Out of scope for v1; flag for later.
4. **Multi-vault.** Support multiple vaults switchable from the UI, or one vault per origin? Current bet: one per origin in the browser, multi in desktop.
5. **Mobile FSA.** Android Chromium 124+ supports `showDirectoryPicker`. Verify behavior, document caveats.
6. **Storage eviction UX.** When to prompt "Install this app to keep your notes safe"? After first note? After three days of use? Needs telemetry-free heuristic.
7. **Frontmatter conventions.** Match Obsidian (so import is trivial) or invent something cleaner? Default to Obsidian-compatible.

---

## 10. Tech stack summary

| Layer | Choice | Locked-in? |
|---|---|---|
| Package manager | pnpm 10 | Yes |
| Task runner | Turborepo 2 | Yes |
| Language | TypeScript 5.9 (strict, bundler resolution) | Yes |
| UI framework | Svelte 5 (runes) | Yes |
| Build tool | Vite 8 | Yes |
| Editor | CodeMirror 6 + `@codemirror/lang-markdown` + `@codemirror/language-data` | Yes |
| Markdown parser (for index / non-editor use) | `remark` + `micromark` (GFM) | Provisional |
| Local storage | OPFS (default) + FSA (upgrade) + native (Tauri) | Yes |
| Index | `sqlite-wasm` + FTS5 | Provisional, M3 |
| Plugin sandbox | `iframe` + `comlink` | Provisional, M5 |
| Desktop shell | Tauri 2 | Provisional, M7 |
| Sync | TBD | M8 |

---

## 11. Non-functional targets

- **Cold load (PWA, second visit):** < 500ms to interactive on a 2020-era laptop, broadband.
- **First note open:** < 50ms after click.
- **Typing latency:** < 16ms end-to-end (one frame at 60Hz).
- **Search across 10k notes:** < 200ms full-text.
- **Memory:** under 200MB resident for a 10k-note vault.
- **Bundle size (main chunk gzipped):** under 200KB target; current ~123KB.
- **Accessibility:** WCAG 2.1 AA contrast for both themes; full keyboard navigation; no focus traps.

---

## 12. What this document is and isn't

**Is:** the single place where intent, scope, and architecture live. The contract between today's decisions and tomorrow's implementation.

**Isn't:** an implementation plan, sprint backlog, or design system catalog. Those live elsewhere (tasks, design files, code).

When the code and the spec disagree, the spec is wrong until reconciled. Update this file whenever a decision changes.
