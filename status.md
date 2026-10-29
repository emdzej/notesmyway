# Status

Last updated 2026-10-29. See `spec.md` for the design.

## Done

- **Spec rewritten** for the native Apple + Go server architecture. The old web prototype is archived in `legacy/` (`legacy/spec-web.md`, `legacy/status-web.md`).
- **M0: engine multiplatform** (in `../swift-markdown-engine`, branch `main`)
  - `b418c7f`: committed the pending Core/dynamic-wrapper split.
  - `7926d88`: parser, styler, renderer and both bridges compile for iOS (`Platform/Platform.swift` holds the aliases and shims; the AppKit view layer is behind `#if os(macOS)`).
  - `e3e63e0`: UIKit editor (`TextView/UIKit/`) and an iOS demo app (`Demo/iOS`, run `xcodegen` there).
  - `b14a578`: removed the screenshot-only `-tail` demo flag.
  - `07b635c`: removed wikilinks and wiki embeds (`[[…]]`, `![[…]]` render as plain text). Images use `ImageProvider` / `ImageRequest(source:)`, and `onLinkClick` gets every link destination.
- **M1: WYSIWYG tables** (spec §4.3)
  - `1514f59`: macOS grid (`TableGridView`), `MarkdownTable` model, `TableGridLayout`, "Edit as Markdown" reveal policy, undo/redo binding sync.
  - `01a1b3d`: shared key behaviour and context-menu commands (`TableGridNavigation`).
  - `6f45226`: iOS grid (`TableGridUIView`), growing cell editors, and two iOS fixes: programmatic edits no longer get smart dashes (a table's `---` was becoming `—`), and system fonts no longer resolve to Times after a restyle.
- **File drops**
  - `7b6f746`: `onDropFiles` hook on macOS and iOS. Dropped files go to the embedder, which stores them and returns the markdown to insert at the drop point (one undoable edit); `DroppedFile.markdownLink(to:)` builds image / file links.
- **Image and link attributes** (spec §3.5)
  - `a3f6bf3`: `{…}` after images and links parsed into `MarkdownAttributes` and hidden off-caret. Images honour `.icon` (inline), `.small` / `.medium` / `.large` / `.full`, `width=` / `height=`, `.left` / `.center` / `.right`, and the Obsidian `|200` alt hint. On macOS, image paragraphs restyle when the column width changes (iOS already rebuilt on width change). Links keep their attributes but render as plain links until preview cards land.
- **Link preview cards** (spec §4.4, engine side)
  - `4e8f165`: `LinkPreviewProvider` service and card rendering (`.small`, `.medium`, `.large`, `.full`, sized and aligned like images), source-above-card while the caret is on the link, inline `.icon`, an "unavailable" badge, loading fallback. Both platforms restyle when a provider's fingerprint changes (the UIKit wrapper ignored image fingerprint changes before).
  - Fix: link destinations without `://` (relative note paths, `mailto:`) reached `onLinkClick` as `https://…`; they now arrive as written, which note links in M3 depend on.
- **Rename:** "vault" is now "notebook" everywhere (spec, status, code). Obsidian vaults open as notebooks.
- **M2 (in progress): `apple/Packages/NmwCore`** (Swift 6, GRDB 7.11, macOS/iOS 26)
  - `Notebook` / `NotebookPath` (NFC, `..`-safe, notebook-relative), `NotebookScanner` (skips hidden files and folders), `Notebook.root(enclosing:)` (finds a `.nmw/` or `.obsidian/` folder above a file).
  - `NoteFile`: coordinated, atomic read/write for any URL (notebook or standalone); refuses to overwrite a file changed on disk (`changedOnDisk` carries the current text); keeps a UTF-8 BOM and line endings; rejects non-UTF-8 files.
  - `Frontmatter`: reads scalars and both list styles; edits one key in place (rest of the block and file untouched, CRLF kept), adds/removes the block as needed.
  - `NoteMetadata`: title (H1 / setext / file name), snippet, tags (frontmatter + inline, nested, not in code), links and images (nested, reference definitions, not in code spans), first image, pinned, created, search text.
  - `LinkTarget.resolve`: relative / `/`-rooted / percent-encoded paths, fragments, schemes, anchors; works the same for standalone files.
  - `NotebookIndex` (spec §6 schema) and `NotebookIndexer` actor: full `sync()` (re-reads only changed size/mtime), `update(paths)`, notes by folder and sort (pinned first), backlinks, tags with nesting, FTS search (prefix, diacritics-insensitive, all words, `tag:` / `path:` / `#tag`, FTS syntax inert).
  - Moves: `NotebookIndexer` reports `moved` (gone + new file with the same unique hash) from both `sync()` and `update()`; folder paths cover their contents. `NotebookIndex.linkEdits(for:)` + `LinkRewriter` compute the edits that keep links working (backlinks and the moved note's own links); nothing is written, the app applies them in M3.
  - `NotebookWatcher`: FSEvents on macOS, a folder `NSFilePresenter` on iOS, coalesced; `NotebookWatcher.changes(of:)` streams `IndexChanges`.
  - `AttachmentStore`: `_attachments/<note>/` at the notebook root (next to the file when standalone), names kept, " 2" / " 3" on clashes, identical files reused; returns the relative link path.
  - `LinkPreviewStore` + `HTMLMetadata`: synchronous lookups for the editor (`.loading` then a `version` bump), web pages from their meta tags (persisted in `link_previews`, images in a cache folder, 7-day refresh, networking switchable off), notes from the index or the file, other files via QuickLook thumbnails with kind and size.
  - `apple/project.yml`: xcodegen multiplatform app skeleton linking NmwCore and the engine, `.md` registered as a document type. Builds for macOS and iOS; UI is M3.
- **M3 (first cut): the app** (`apple/Packages/NmwUI`, app target in `apple/project.yml`)
  - `Library`: notebooks as security-scoped bookmarks, one `NotebookSession` each; routes opened `.md` files into their notebook or a standalone window.
  - `NotebookSession`: sync + watcher, scopes (All, Pinned, folder, tag) with search inside them, sort; new note (`Untitled.md`, `Untitled 2.md`), rename / move with automatic link fixing and a one-click undo banner, pin (frontmatter), move to `.nmw/trash/`. Open editors follow moves and reload outside edits.
  - `NoteEditorModel`: 500 ms autosave, outside edits adopted when nothing is unsaved, otherwise a conflict bar (Keep Mine / Use Disk Version / Keep Both, which saves a `(conflict …)` copy); non-UTF-8 files open read-only.
  - Editor wiring: images and preview cards resolve relative to the note, drops go to `AttachmentStore` (`![](…){.medium}` for images), link clicks open notes / files / URLs, "Link to Note…" (⌘L) fuzzy picker inserts `[Title](relative.md)`.
  - Views: three-column `NavigationSplitView` (notebook menu, All / Pinned, folder tree, tags with counts; note list with date, snippet, first-image thumbnail, context menu; editor), welcome screen, standalone-file windows (macOS) / sheet (iOS). Commands: New Note ⌘N, Link to Note ⌘L, Open File… ⇧⌘O, Add Notebook….
  - Added since: quick switcher (⌘O), inspector (⌥⌘I) with the outline (click jumps to the heading) and backlinks, folder context menu (New Folder, Rename… with link fixing, Move to Trash), "create it?" for links to missing notes, undo of nmw's own rename / move (the banner's Undo moves the file back and restores links), trash entries older than 30 days purged on open, standalone folder-access bar (sandbox; grant kept as a bookmark).
  - macOS app is sandboxed (user-selected files, app-scope bookmarks, network client) and ad-hoc signed for local runs.
  - Engine `38bc138`: `MarkdownEditorController.reveal(_:)`; `b746644`: macOS editor stays at the top when its viewport resizes (a bar appearing above it hid the first lines) and applies `safeAreaInsets` changes.
  - Engine `cd8ab36`: `MarkdownEditorController` (insert at the caret in one specific editor, `focus()`), and the UIKit wrapper takes `onDropFiles` before `onLinkClick` like AppKit.
- **Name and look:** the app is "Notes my Way" (abbreviation nmw everywhere: `NmwCore`, `NmwUI`, `.nmw/` notebook folder, settings keys), bundle ID `pl.emdzej.notesmyway`. App icon: cream page with a teal `#` on a teal-to-navy gradient (`design/icon-proposals/5-paper-hash-teal-a.png`, generated with fal `google/nano-banana-2.1`), rendered as an iOS full-bleed 1024 and a macOS rounded-square set. Accent `#0B6E8E` / `#3AB7CF` (dark) for controls and editor links.
- **Subfolders:** the sidebar tree starts expanded with visible arrows; selecting a folder lists its notes and its subfolders' notes (with the subfolder as a caption).
- **Tests**
  - Package (`swift test`, macOS): 144 pass, including end-to-end grid editing in a real window (cell edit, Tab, add row, Esc, undo/redo, context menu, Edit as Markdown, arrow into table).
  - NmwCore (`swift test` in `apple/Packages/NmwCore`): 57 pass (adds the outline), on real temp folders (scan, sync, change detection, queries, file conflicts, BOM / CRLF, standalone files, link rewriting, rename and folder-move detection, FSEvents watcher end to end, attachments, HTML parsing, previews with a stubbed URLSession). Also builds for iOS.
  - NmwUI (`xcodebuild test -scheme NmwUI -destination 'platform=macOS'` in `apple/Packages/NmwUI`; `swift test` can't link the engine's dynamic product there): 18 pass (run from clean derived data; an incremental `build` then `test` can fail to link), covering folder create / rename / trash, missing-note creation, trash expiry, undo of a rename, and autosave, conflicts, own-save vs outside-change, rename + link fix + undo, moves through an open editor, pin, trash, an FSEvents edit reaching an open editor, drops, link classification, the picker's ranking.
  - Engine: 145 pass (the controller adds an AppKit insert-at-selection test).
  - Ran the real app: macOS (sandboxed) opened a standalone `.md` via `open -a`, with code highlighting; iOS simulator shows the welcome screen. A hosted snapshot of the three columns on a sample notebook looked right.
  - iOS (`xcodebuild test` on the `MarkdownEngineDemoiOS` scheme): 6 editor tests (grid + file drop) hosted by the demo app (package tests on iOS have no window scene).

## Not yet verified

- Typing with a real software keyboard on device; the keyboard-keeper hand-off between cells is only exercised in tests.
- iOS editor basics outside tables: caret-driven marker reveal, list continuation on Enter, checkbox taps, link taps, IME/marked text.
- Wide tables (horizontal scroll) with an active cell editor, on both platforms.
- File drops from real drag sessions: tests call the insertion directly. Finder / Files / Photos drags should be tried by hand.
- Image attributes and preview cards on iOS: shared styler code, covered by macOS tests; the iOS editor tests still pass but don't exercise cards. Layout was checked in macOS snapshots only (light mode; dark mode not looked at).
- Clicking a card: relies on the card's anchor character keeping the link attribute; covered by reasoning, not by a click test.
- NmwCore on large notebooks (thousands of notes): `sync()` reads changed files serially; no timing yet.
- The iOS watcher (folder file presenter) compiles but isn't exercised by tests; presenters only hear about coordinated writes.
- Move detection needs both halves of a rename in one event batch; FSEvents delivers them together in testing, but a slow or split delivery would show as remove + add (no link rewrite).
- QuickLook thumbnails in previews: the test only covers a file whose thumbnail may fail (an empty PDF); real thumbnails aren't checked.
- NmwCore inside the app sandbox and with iCloud placeholders (not-downloaded files fail to read and land in `failed`); both are untested until M3 / M5.
- File promises (images dragged out of Safari or Photos on macOS arrive as promises, not file URLs) are not handled yet.

## Known gaps (UIKit editor)

- Size menu for images and cards (context menu / pinch) is not built yet (M4).
- Not ported from AppKit yet: code-block copy button, find, Writing Tools hooks, placeholder, scroll-away header, reading column, paste-image handling.
- Code-block background selection cut-out depends on `textLayoutManager.textSelections`, which UITextView may not keep in sync.
- On macOS, the input handlers edit via `shouldChangeText` + `replaceCharacters` + `didChangeText` instead of `insertText(_:replacementRange:)`. Both are undoable, but LaTeX block auto-wrap deserves a manual check.

## Known gaps (app)

- Not built yet: command palette (⌘K), "Move to Notebook…" for standalone files, H1 auto-rename setting, iOS swipe actions and keyboard accessory bar, find & replace UI, restoring from the trash, drag-to-move in the sidebar.
- An image that can't be loaded shows as its file name (markers hidden) rather than as dimmed markdown; engine behaviour.
- Verified in the running sandboxed macOS app: the folder-access bar appears for a standalone note whose folder isn't granted, and the text starts below it. Not clicked through: the Allow panel itself.
- Not tried by hand: picking a folder, typing and autosave in the running app, drag and drop, renames from the context menu, preview cards fetching real pages, iPad layout, iOS notebook flow (only the welcome screen was looked at).

## Next

1. Try the app by hand on macOS and iPad (list above), fix what turns up.
2. M3 leftovers: command palette, Move to Notebook…, iOS swipe actions and accessory bar, find & replace.
3. M4 polish (size menu for images and cards), then M5 iCloud.
