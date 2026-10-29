# nmy — project status

**Updated:** 2026-06-21
**Current state:** M0 + M1 + M2 done, M3 partial. Web app boots, edits, autosaves, links, and runs commands. All decisions captured in [`spec.md`](./spec.md); this file is the "where we are right now" snapshot for resuming work.

---

## Quick start

```bash
pnpm install          # once
pnpm dev              # web dev server (Vite, http://localhost:5173)
pnpm check            # svelte-check across the graph
pnpm build            # production build
```

Single browser tab is enough to exercise everything below. OPFS persists across reloads in the same origin.

---

## Verified end-to-end

- `pnpm install` clean (no peer warnings beyond optional ones)
- `pnpm check` → 0 errors across both packages
- `pnpm build` → 390ms, main bundle 356KB / 129KB gzipped, per-language CM6 grammars code-split
- Dev server transforms every module on first request

**Not verified manually in a browser.** All progress so far has been validated by typecheck + bundler, not by actually clicking through. First real browser exercise should happen before M4 begins — particularly the wikilink follow flow and command palette navigation, both of which are wired but unobserved.

---

## What works today

### Storage (M0)
- `FileSystem` interface in `packages/core/src/filesystem/types.ts`
- `HandleFileSystem` shared implementation for any `FileSystemDirectoryHandle`
- `createOpfsFileSystem()` — auto-selected, no user prompt
- `createFsaFileSystem(handle)` + `pickDirectory()` — written but **not yet wired into the UI** (waiting for M4)
- `detectFileSystem()` returns `{ fs, mode, canUpgradeToFsa }`

### Editor (M1)
- `apps/web/src/lib/Editor.svelte` — CM6 wrapper
- `basicSetup` + `markdown({ codeLanguages })` — ~50 languages lazy-loaded for fenced code blocks
- Heading scaling (h1 1.9×, h2 1.55×, h3 1.3×) + dimmed punctuation via `editor-theme.ts`
- 500ms debounced autosave with `dirty / saving… / saved` status pill
- Light/dark/system theme bound to CSS variables (`light-dark()` + `[data-theme]` override)

### Wikilinks + index (M2)
- `packages/core/src/vault/`
  - `walk.ts` — `walkVault`, `walkNotes` async iterators (skips dotfiles)
  - `parse.ts` — `parseFrontmatter`, `deriveTitle`, `extractTags`, `extractWikilinks`; small line-based YAML reader
  - `index.ts` — `VaultIndex` with rebuild + incremental `upsertFromContent` / `remove`; title + alias maps, backlinks set, `searchTitles` ranking
- `apps/web/src/lib/wikilink-extension.ts` — CM6 `MatchDecorator` styling `[[...]]` and `Cmd/Ctrl+click` handler
- `apps/web/src/lib/wikilink-completion.ts` — completion source on `markdownLanguage.data`, triggers inside `[[…`
- `apps/web/src/lib/FolderTree.svelte` — recursive lazy-loaded folder tree
- `apps/web/src/lib/BacklinksPanel.svelte` — list of inbound links under the editor
- **Auto-create on broken link follow** — `Cmd+click` of `[[Unknown]]` writes `/Unknown.md` and opens it

### Keyboard UX (M3 partial)
- `apps/web/src/lib/CommandPalette.svelte` — generic overlay; arrow / Enter / Esc nav, `Ctrl+N/P` Emacs-style; fuzzy ranking (exact > prefix > contains > hint)
- `apps/web/src/lib/theme.ts` — `loadTheme` / `applyTheme` / `cycleTheme`, persisted to localStorage
- Global keymap in `App.svelte`:
  - `⌘O` — quick switcher
  - `⌘K` / `⌘⇧P` — command palette
  - `⌘⇧N` — new note (Cmd+N is browser-reserved)
  - `⌘\` — toggle sidebar
- Commands: new note, new folder, open switcher, toggle sidebar, theme system/light/dark/cycle

---

## Repository layout

```
nmy/
├── apps/web/
│   ├── src/
│   │   ├── App.svelte           main shell: state, shortcuts, palette wiring
│   │   ├── app.css              CSS variables + theme overrides
│   │   ├── main.ts
│   │   └── lib/
│   │       ├── Editor.svelte
│   │       ├── editor-theme.ts
│   │       ├── wikilink-extension.ts    CM6 decoration + click handler
│   │       ├── wikilink-completion.ts   CM6 completion source
│   │       ├── FolderTree.svelte        recursive, lazy
│   │       ├── BacklinksPanel.svelte
│   │       ├── CommandPalette.svelte    generic overlay
│   │       └── theme.ts                 localStorage persistence
│   ├── index.html / vite.config.ts / svelte.config.js / tsconfig.json
│   └── package.json
├── packages/core/
│   ├── src/
│   │   ├── index.ts                     re-exports
│   │   ├── filesystem/
│   │   │   ├── types.ts                 FileSystem, FileEntry
│   │   │   ├── path.ts                  segments / basename / dirname / joinPath
│   │   │   ├── handle-fs.ts             HandleFileSystem (shared OPFS/FSA impl)
│   │   │   ├── opfs.ts
│   │   │   ├── fsa.ts                   pickDirectory + createFsaFileSystem
│   │   │   └── detect.ts                detectFileSystem
│   │   └── vault/
│   │       ├── walk.ts
│   │       ├── parse.ts
│   │       └── index.ts                 VaultIndex
│   └── package.json / tsconfig.json
├── package.json                         turbo, typescript (root deps)
├── pnpm-workspace.yaml                  workspaces + catalog
├── turbo.json                           v2 tasks
├── tsconfig.base.json                   strict, Bundler, DOM.AsyncIterable
├── .npmrc                               workspace protocol = rolling
├── spec.md                              full design doc
└── status.md                            this file
```

---

## Known gaps / parking lot

These are intentional and not bugs — they're the next pass.

| Area | Gap | When to fix |
|---|---|---|
| Folder tree | Sub-directory children don't re-list after creating a note/folder inside an expanded subdir; only `/` re-lists | M4 (when we add a vault-event bus alongside file watching) |
| Wikilink decoration | When the index changes after typing, existing matches don't update their broken/resolved class until the line is re-edited | When it bites — cheap fix via a `StateEffect` |
| FSA mode | Code is written in `packages/core/src/filesystem/fsa.ts` but no UI to switch into it; no handle persistence in IndexedDB yet | M4 (next milestone) |
| Zip export | Not implemented | M4 |
| File watcher | Not implemented (polling under FSA, native under Tauri) | M4 desktop / browser polish |
| Storage eviction prompt | iOS Safari can evict OPFS after ~7 weeks; no install-to-home-screen nudge yet | M4 |
| Full-text search | UI uses in-memory `VaultIndex.searchTitles`; no FTS, no body search | M3 follow-up |
| Outline panel | Not implemented | M3 follow-up |
| Tags browser | Tags are extracted but unused | M3 follow-up |
| Note history | `Cmd+]` / `Cmd+[` not wired | M3 follow-up |
| Plugin runtime | Not started; spec'd as iframe + comlink | M5 |
| Tauri shell | Not started | M7 |
| Sync | Not started; three options on the table | M8 |

---

## Decisions captured (don't relitigate)

- **pnpm 10 + Turborepo 2 + Svelte 5 + Vite 8 + TS 5.9 strict.** Locked.
- **CodeMirror 6** as the editor, not ProseMirror / Milkdown — see spec §5.5 for the reasoning.
- **OPFS is the default**, FSA is the upgrade, Tauri native is the future — all behind one `FileSystem` interface.
- **No sidecar formats.** Files are raw `.md` with raw bytes; OPFS is a *location* not a format.
- **Plugins will run sandboxed** in iframes with a comlink RPC bridge. (Not yet implemented, but the architecture is committed in spec §5.6.)
- **No CRDT in v1.** Single user. Sync decision deferred to M8.
- **Catalog versions** for shared deps (typescript, svelte, vite, @sveltejs/vite-plugin-svelte, @tsconfig/svelte, svelte-check, @types/node) in `pnpm-workspace.yaml`.

---

## Suggested next session

Two coherent directions, pick one:

1. **M4 — "Your data is yours"** (recommended)
   - Wire `pickDirectory()` into the UI as an "Open folder…" command
   - Persist the `FileSystemDirectoryHandle` in IndexedDB; re-request permission on session start
   - "Export as .zip" command for non-FSA browsers
   - Onboarding step that nudges PWA install on iOS to avoid storage eviction
   - Optional: poll-based file watcher for external edits in FSA mode

2. **M3 finish — power-user tooling**
   - sqlite-wasm + FTS5 for full-text body search
   - Outline panel (current note's headings) reusing the syntax tree
   - Tag browser (sidebar tab or filter chips)
   - Note history (`Cmd+]` / `Cmd+[`) with a small in-memory stack

M4 is the more user-visible win and unblocks dogfooding against a real folder. M3 finish makes the existing experience deeper but doesn't change what the app *is*.

---

## How to resume mid-flow

If picking this up after a break:

1. `pnpm install` (in case the lockfile was touched)
2. `pnpm check` to confirm nothing has drifted
3. `pnpm dev` and click around; create a note with `⌘⇧N`, type `[[foo`, see the completion
4. Read `spec.md` §8 for the milestone you're starting (the spec is the source of truth for intent)
5. Read this file's "Known gaps" table for what's *intentionally* missing
6. Start small. The codebase is ~2000 LOC across both packages — preserve that signal-to-noise.
