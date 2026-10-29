# nmw — Notes my Way

**Status:** living document. Last updated 2026-10-29. Supersedes `legacy/spec-web.md` (web-first design, archived).
**One-line:** an Apple Notes–feeling, plain-markdown notes app for macOS and iOS/iPadOS. Notes are plain `.md` files in plain folders; the editor blends raw markdown with WYSIWYG.

---

## 1. Principles

1. **Files are the truth.** A notebook is a folder of `.md` files plus attachments. Anything nmw does, you can also do with `vim`, `grep`, `git`, or any other markdown editor.
2. **Blend, don't hide.** Markdown renders in place. Markers like `**` and `#` collapse when the cursor is elsewhere and reappear on the line being edited. The bytes on disk are exactly what you typed.
3. **Native first.** SwiftUI + TextKit 2 on Apple platforms. No web views in the editing path.
4. **Derived data is disposable.** SQLite holds only what can be rebuilt from files. Deleting it never loses data.
5. **Sync is a notebook property.** Each notebook uses exactly one sync mode: none, iCloud, or the nmw server.

### Non-goals (v1)
- Real-time multi-user collaboration or CRDTs.
- Android, Windows, or web clients. The format and sync protocol are specified so these can come later.
- A plugin system. Revisit after v1.

---

## 2. Platforms and stack

| Concern | Choice |
|---|---|
| Targets | macOS 26+, iOS/iPadOS 26+, one multiplatform SwiftUI app target |
| Language | Swift 6 (strict concurrency) |
| Editor | `MarkdownEngine` (our fork of `nodes-app/swift-markdown-engine`), extended to UIKit |
| Index | SQLite via GRDB.swift with FTS5 |
| Sync server | Go, standard library `net/http`, `modernc.org/sqlite`, content-addressed blob store |
| Code highlighting / math | `MarkdownEngineCodeBlocks` (HighlighterSwift) / `MarkdownEngineLatex` (SwiftMath) |

### Repository layout

```
nmw/
  apple/
    project.yml                 xcodegen spec for the multiplatform app (nmw.xcodeproj is generated)
    App/                        app sources
    Packages/
      NmwCore/                  notebook, file watching, frontmatter, markdown extensions, index (GRDB)
      NmwUI/                    app models and SwiftUI views (library, sessions, editor wiring)
      NmwSync/                  SyncProvider protocol, iCloud + server providers, 3-way merge
  server/                       Go module: nmw-server
  spec/
    format.md                   nmw markdown dialect (normative)
    sync-protocol.md            server sync protocol (normative)
  legacy/                       archived Svelte/web prototype
../swift-markdown-engine        editor package (separate repo, consumed as a local SPM dependency)
```

---

## 3. Notebook format

### 3.1 Layout

```
<notebook>/
  Inbox.md
  Projects/
    Idea.md
  _attachments/
    Idea/
      sketch.jpg                original file names; " 2", " 3" appended on clashes
  .nmw/
    config.json                 notebook settings (synced)
    trash/                      soft-deleted notes, kept 30 days
```

- Any folder can be a notebook. Obsidian vaults open as notebooks, and `.obsidian/` is ignored, but their `[[wikilinks]]` show as plain text (see 3.3).
- Folders are real folders, with unlimited nesting.
- Files and folders starting with `.` are hidden in the UI. `_attachments/` is shown only in "Show attachments".
- Text encoding is UTF-8. Line endings are preserved as read; new files use `\n`.

### 3.2 Frontmatter

Optional YAML. nmw never requires it, and only writes keys the user set through the UI:

```yaml
---
tags: [project, idea]
pinned: true
created: 2026-10-29T10:00:00Z
---
```

- **Title** = first `# H1` (or setext `===` heading), else the file name.
- **Auto-rename** (renaming the file to follow the H1, as Apple Notes does) is a setting, **off by default**, so file names stay stable for git and other tools.
- Anything that must sync per note (pin, tags) lives here, never only in SQLite.

### 3.3 Markdown dialect

The baseline is CommonMark + GFM: tables, task lists, strikethrough, autolinks, footnotes. Extensions:

| Syntax | Meaning | Compatible with |
|---|---|---|
| `#tag`, `#nested/tag` | Inline tag | Obsidian |
| `$…$`, `$$…$$` | Inline / block math | Obsidian, Pandoc |
| `> [!note] Title` | Callout | Obsidian |
| `{.class key=value}` after an image or link | Attributes, see 3.5 | Pandoc, kramdown, markdown-it-attrs |

**No wikilinks.** `[[Note]]` and `![[image]]` are not CommonMark, so nmw does not parse them; they render as plain text. Notes link to each other with standard links to relative paths, so the links work on GitHub, in other editors, and in static-site generators:

```markdown
[Project idea](Projects/Idea.md)
[See setup](../Guides/Setup%20Guide.md#install)
```

### 3.4 Standalone files

nmw also opens a single `.md` file that isn't in a notebook (Finder "Open With", double-click, the Files app, drag onto the Dock icon).

- **Same core:** reading, saving, metadata, and link resolution in `NmwCore` work on a file URL, so a standalone file behaves like a notebook note: coordinated atomic saves, external-change detection, a byte-order mark and line endings kept as found.
- **Relative links and images** resolve against the file's folder. A `/`-rooted link has no notebook root, so it resolves against the folder too.
- **Not indexed:** no backlinks, tags, or search across files; the outline and the note's own tags still work.
- **In a notebook already?** If the file sits inside a folder that is an open notebook, or under a folder marked `.nmw/` or `.obsidian/`, nmw offers to open it in that notebook instead.
- **Dropped files** go to `_attachments/<file name>/` next to the file, as in a notebook.
- **Sandbox:** opening a file grants access to that file only. Showing sibling images and writing attachments need the folder; nmw asks for it once (a folder picker preselected to the file's folder) and keeps a security-scoped bookmark.
- The window has no sidebar; "Move to Notebook…" copies the file (and the attachments it links to) into a notebook.

### 3.5 Attributes on images and links

A `{…}` block directly after an image or a link carries display attributes. The same size vocabulary applies to both.

```markdown
![Diagram](_attachments/Idea/3f2a.jpg){.small}
![](logo.png){.icon}
![](photo.jpg){.large .center}
![](chart.png){width=320}

[Swift Evolution](https://www.swift.org/swift-evolution/){.preview}
[Q3 report](_attachments/Q3.pdf){.preview .large}
[Project idea](Projects/Idea.md){.preview .small}
```

| Attribute | On an image | On a link |
|---|---|---|
| `.preview` | (images always render) | Render a preview card instead of plain link text, see 4.4 |
| `.icon` | line height (inline, ~1.2em) | Favicon / file icon + title, inline |
| `.small` | 160 pt max width | Compact one-line card: icon, title, host or file size |
| `.medium` | 320 pt max width (default for pasted images) | Card: thumbnail, title, description (default for `.preview`) |
| `.large` | 640 pt max width | Large card: full-width hero image, title, description |
| `.full` | full text-column width | Like `.large`, edge to edge |
| `width=N` / `height=N` | explicit points; with both, the image fits inside that box (aspect ratio always kept) | Card width / thumbnail height |
| `.left` `.center` `.right` | alignment of the block image | Alignment of the card |

- A size attribute on a link implies `.preview`.
- The block must follow the `)` directly (no space) and be valid attribute syntax (`.class`, `#id`, `key=value`, `key="…"`); otherwise it is ordinary text.
- `.small` / `.medium` / `.large` cap the width and never upscale; no image grows past the text column.
- Unknown attributes are preserved byte-for-byte and ignored.
- Without attributes, links render as ordinary styled links; nmw never previews a link on its own.
- On read, nmw also accepts the `![alt|200](img.png)` width hint (valid CommonMark, used by Obsidian). nmw rewrites it to the brace form only when the user changes the size through the UI.
- The size menu (context menu or pinch on iOS) edits the brace attributes in the source; the link context menu offers "Show Preview" (adds `{.preview}`) and the sizes.
- Other renderers show the `{…}` text after the link or image, but the link itself still works.

---

## 4. Editor

### 4.1 Model
- The text storage holds the exact file contents. Styling is attributes only, and markers are never removed from storage. This is the engine's core invariant.
- **Active vs. inactive constructs:** a construct containing the caret or selection shows its markers (dimmed). All others collapse their markers to near-zero width.
- Images, math, checkboxes, and rules render as attachments or overlays when inactive.
- Parsing is incremental, block-scoped, and roughly O(edit) per keystroke.

### 4.2 Feature set (v1)
- Headings, emphasis, strikethrough, inline code, links, blockquotes, callouts, horizontal rules.
- Lists with continuation on Enter, indent and outdent on Tab / Shift-Tab, and tappable task checkboxes.
- Fenced code with syntax highlighting and a copy button.
- Inline and block math.
- Inline images and link previews with attribute-driven sizing (3.5, 4.4).
- **Adding files:** drop any file onto the editor (or paste / camera / scan an image on iOS). nmw copies it to `_attachments/<note>/` (name kept, ` 2`, ` 3` … appended on clashes) and inserts a link at the drop point: `![](…){.medium}` for images, `[name](…)` for other files (add `{.preview}` for a card, 4.4). The engine hands drops to nmw through its `onDropFiles` hook and inserts the returned markdown as one undoable edit.
- **Note links:** "Link to note" (Cmd-L, or the iOS accessory bar) opens a fuzzy picker over the index and inserts `[Title](relative/path.md)`, with the path percent-encoded. Cmd-click (macOS) or tap (iOS) on a relative `.md` link opens that note; a link to a missing note offers "create".
- Tags with `#` autocomplete.
- Find and replace, spelling (suppressed in code, math, links), Writing Tools.
- An iOS keyboard accessory bar for formatting, checkbox, image, link, and indent.

### 4.3 WYSIWYG tables
GFM tables are edited as a live grid, not as pipe text. Implemented in the engine for macOS and iOS (`TableGridView` / `TableGridUIView`).

- **Rendering:** the table's source stays in text storage with its glyphs collapsed to one anchor line that reserves the table's height. A grid view sits over that line, draws the rendered table, and scrolls horizontally when the table is wider than the text column. The picture and the grid share one layout (`TableGridLayout`), so clicks land on the cell you see.
- **Cells:** click (macOS) or tap (iOS) a cell to edit its raw inline markdown in a field that grows with the text; leaving the cell renders it formatted again. This is the same raw-while-editing blend as the rest of the editor.
- **Keys:** Tab / Shift-Tab move to the next / previous cell, wrapping rows; Tab past the last cell adds a row. Return moves down and adds a row from the last row. Up / Down move between rows and leave the table at its edges. Esc discards the cell's change and leaves the table. On iOS these work with a hardware keyboard; the software keyboard's Return key moves down.
- **Structure:** a context menu (right-click on macOS, long-press on iOS) inserts, deletes, and moves rows and columns and sets alignment (`:--`, `:-:`, `--:`).
- **Write-back:** committing a cell or a structural change rewrites the table as normalized GFM (columns padded to align, `|` escaped as `\|`) in one undoable edit.
- **Caret:** a caret moved into a table by the arrow keys enters its grid; the raw pipe source is never revealed by accident.
- **Escape hatch:** "Edit as Markdown" in the context menu shows the raw pipe source with the caret in it; moving the caret out of the table turns it back into a grid.
- **Model:** `MarkdownTable` parses and serializes GFM tables (escape-aware, header/delimiter column count wins, short rows padded) and performs the structural edits; `TableGridNavigation` holds the shared key behaviour and menu commands.

### 4.4 Link previews
A link marked `{.preview}` (or any size attribute) renders as a preview card in place of its text. It uses the same blend as images: the card shows while the caret is elsewhere; with the caret on the link, the raw markdown shows and the card stays below it.

| Target | Preview source |
|---|---|
| Web page (`http`, `https`) | One GET of the page; OpenGraph / Twitter / `<meta>` / `<link rel=icon>` tags give title, description, site name, hero image, icon (`LinkPresentation` exposes no description, so it isn't used) |
| Note in the notebook (`Other.md`) | From the index: title, first lines of the note, first image |
| File in the notebook (PDF, image, office doc, …) | `QuickLookThumbnailing` (`QLThumbnailGenerator`) thumbnail, file name, size |
| Unreachable / missing | Plain link styling with a muted "unavailable" badge |

- **Network:** only links the user explicitly marked are fetched; there is no background crawling of other links. A notebook setting turns web previews off entirely.
- **Cache:** fetched metadata and thumbnails live in the per-device index (`link_previews` table, section 6) and an on-disk image cache. Both are derived, never synced, and safe to delete. Entries refresh after 7 days or on "Refresh Preview".
- **Editing:** clicking a card opens the link (Cmd-click on macOS, as for other links); the context menu changes the size, refreshes, or removes the preview (deletes the attribute).
- **Placement:** a card replaces a link that is alone on its line. A `{.preview}` link inside a sentence stays an ordinary link; `{.icon}` works anywhere.
- **Engine** (done): the engine renders cards from data supplied by a `LinkPreviewProvider` service. Lookups are synchronous and return `LinkPreview` (`.ready`, `.loading`, `.unavailable`) or nil for a plain link; the provider changes its `fingerprint()` when a fetch completes, and the editor restyles. Fetching and caching live in the app (`NmwCore`), not in the engine.

### 4.5 Engine work (in `swift-markdown-engine`)
1. **Multiplatform** (done): platform typealiases (`PlatformFont`, `PlatformColor`, `PlatformImage`, …) so Parser, Styling, Renderer, Configuration, Input, and Services compile for macOS and iOS. The TextView layer is split into `TextView/AppKit` (existing) and `TextView/UIKit` (new: a `UITextView` subclass, a `UIViewRepresentable` wrapper, and a coordinator).
2. **No wikilinks** (done): `[[…]]` / `![[…]]` render as plain text, and images go through `ImageProvider` / `ImageRequest(source:)`.
3. **Attributes** (done): `{…}` after images and links is parsed into `MarkdownAttributes` and hidden like other markers; images are sized and aligned by it, `.icon` renders inline.
4. **Table grid overlay** (done): as described in 4.3.
5. **Callouts and `#tags`:** styling.
6. **Link preview cards** (done): `LinkPreviewProvider` service, card rendering in the four sizes, raw-on-caret blend (4.4).
7. **File drop hook** (done): `onDropFiles` on macOS and iOS; `DroppedFile.markdownLink(to:)`.

---

## 5. App UX

Apple Notes structure, Obsidian power:

- **Folders:** the sidebar shows the folder tree expanded; a folder lists its own notes and those in its subfolders (captioned with the subfolder). The notebook root lists only its own notes (All Notes lists everything).
- **Three columns** (`NavigationSplitView`): sidebar with notebooks, folders, tags, and Pinned / Recent / Trash; note list with title, date, two-line snippet, and thumbnail of the first image; editor. iPhone collapses to a stack.
- **Note list:** sort by modified, created, or title. Pinned notes on top. Swipe actions on iOS: pin, move, delete.
- **New note:** Cmd-N, or a toolbar button that creates `Untitled.md` and focuses it. The file name follows the H1, debounced.
- **Search:** a toolbar search field. FTS over titles and bodies, plus `tag:` and `path:` filters.
- **Quick switcher** (Cmd-O) and command palette (Cmd-K) on macOS. "Open File…" is Shift-Cmd-O.
- **Conflicts while editing:** an outside change is adopted silently when the editor has no unsaved text; otherwise a bar offers Keep Mine, Use Disk Version, or Keep Both (saves the other version as `Note (conflict <date>).md`).
- **Panels:** backlinks and outline, as an inspector on macOS and iPad, or a sheet on iPhone.
- **System integration:** Spotlight (CoreSpotlight), a Share extension that appends to Inbox or creates a note, widgets (pinned or recent notes), App Intents / Shortcuts, Quick Note on macOS.
- **Saving:** autosave 500 ms after the last keystroke, with coordinated writes. There is no save button.

---

## 6. Index (SQLite)

- **Location:** `Application Support/nmw/index/<notebook-id>.sqlite`, per device. Never stored inside the notebook, never synced.

```sql
CREATE TABLE files (
  id        INTEGER PRIMARY KEY,
  path      TEXT UNIQUE NOT NULL,   -- notebook-relative, NFC-normalized
  kind      TEXT NOT NULL,          -- 'note' | 'attachment' | 'other'
  hash      TEXT,                   -- sha256 of contents (rename detection, sync)
  size      INTEGER,
  mtime     INTEGER,
  downloaded INTEGER NOT NULL DEFAULT 1   -- 0 = iCloud placeholder
);
CREATE TABLE notes (
  file_id   INTEGER PRIMARY KEY REFERENCES files(id) ON DELETE CASCADE,
  title     TEXT NOT NULL,
  snippet   TEXT,
  pinned    INTEGER NOT NULL DEFAULT 0,
  created   INTEGER,
  first_image TEXT
);
CREATE TABLE tags    (file_id INTEGER REFERENCES files(id) ON DELETE CASCADE, tag TEXT);
CREATE TABLE links (
  src_id    INTEGER REFERENCES files(id) ON DELETE CASCADE,
  target    TEXT NOT NULL,          -- raw destination as written
  target_path TEXT,                 -- notebook-relative path it resolves to (NULL = external URL)
  kind      TEXT NOT NULL           -- link | image
);
CREATE TABLE link_previews (
  url       TEXT PRIMARY KEY,       -- resolved URL or notebook-relative path
  title     TEXT,
  summary   TEXT,
  icon_path TEXT,                   -- cached image files (derived)
  image_path TEXT,
  subtitle  TEXT,                   -- site name / host
  fetched   INTEGER,
  status    TEXT                    -- ready | unavailable
);
-- rowid = files.id. Stores its text (not contentless) so a changed note's row can be replaced.
CREATE VIRTUAL TABLE notes_fts USING fts5(title, body, tokenize='unicode61 remove_diacritics 2');
```

- **Indexing:** a full scan on first open; later scans (launch) only re-read files whose size or mtime changed. While open, file events drive it: FSEvents on macOS (it also sees uncoordinated writers such as vim, git, and Syncthing), an `NSFilePresenter` on the notebook folder on iOS, and `NSMetadataQuery` for iCloud (M5). Events are coalesced (~0.3 s); a folder event covers everything inside it, and a dropped-events signal triggers a full scan.
- **Resolution:** a link destination is percent-decoded and resolved against the folder of the source note at index time, giving `target_path`. Backlinks are `SELECT src_id FROM links WHERE target_path = ?`.
- **Renames:** when one batch of changes (or a launch scan) has a file gone and a new file with the same sha256, and the match is unique, it is a move. The app then rewrites links (default on, with an undoable summary) so they never silently break: links *to* the moved file in other notes, and the moved note's *own* relative links when it changed folders. Only changed destinations are rewritten; `/`-rooted links stay rooted, `<…>` stay angled, fragments and titles are kept. Saves use the text the edit was computed from, so a concurrent change is never overwritten.

---

## 7. Sync

```swift
protocol SyncProvider {
  func start(notebook: Notebook) async throws
  func stop() async
  var status: AsyncStream<SyncStatus> { get }
}
```

### 7.1 None
The notebook is a local folder or any user-picked folder (security-scoped bookmark). External sync tools such as Syncthing or Dropbox work through file watching.

### 7.2 iCloud
- **Location:** notebooks live in the app's ubiquity container, `iCloud Drive/nmw/<Notebook>/`, which is visible in Files and Finder.
- **Discovery:** `NSMetadataQuery`. Placeholders are downloaded on demand, with eager download for notes smaller than 1 MB.
- **File access:** all reads and writes go through `NSFileCoordinator`, and the open note registers as an `NSFilePresenter`, so external edits reload live.
- **Conflicts:** `NSFileVersion.unresolvedConflictVersionsOfItem`. nmw first tries a 3-way merge, using the last version it wrote as the base. If the merge is clean, nmw resolves the conflict silently. Otherwise it keeps both copies, saving the other one as `Note (conflict <device> <date>).md`.

### 7.3 nmw server (self-hosted, Go)
Full protocol in `spec/sync-protocol.md`. Summary:

- **Model:** per notebook, the server stores a **change log** of `(rev, path, hash | deleted, device, ts)` with a monotonic `rev`, plus a **blob store** keyed by sha256.
- **Pull:** `GET /v1/notebooks/{id}/changes?since=<rev>` returns the changes and the new cursor. Missing blobs come from `GET /v1/blobs/{hash}`.
- **Push:**
  1. `PUT /v1/blobs/{hash}` uploads the blob; the upload is idempotent.
  2. `POST /v1/notebooks/{id}/commit` sends `[{path, base_rev, hash|deleted}]`.
  3. The server rejects entries whose `base_rev` is not the path's latest revision, and returns a 409 with the current state for each rejected path.
- **Conflicts:** the client keeps a shadow copy of each file's last-synced content, the base. On a 409 it 3-way-merges base, local, and remote text. A clean merge is committed; a failed merge produces a conflict copy. Binary files are last-writer-wins, with a conflict copy.
- **Live:** `GET /v1/notebooks/{id}/events` (WebSocket) pushes `rev` notifications, and clients pull on notify. Clients also poll every 60 s as a fallback.
- **Auth:** device pairing. An admin creates a one-time code, and the device exchanges it for a long-lived device token (Bearer). Tokens are revocable per device.
- **Server storage:** SQLite for the log, devices, and notebooks; blobs on disk at `blobs/ab/cd/<hash>`. Old blob versions are garbage-collected after N days.
- **Deploy:** a single static binary plus Docker image, configured via env/flags, with TLS via a reverse proxy or the built-in autocert.
- **Later:** optional end-to-end encryption. Encrypt blobs and paths with a notebook key, so the server only ever stores ciphertext.

### 7.4 Rules
- Each notebook uses exactly one provider. Putting a server-synced notebook inside iCloud Drive is refused, with an explanation.
- Writes are atomic: write a temp file, then use a coordinated replace.

---

## 8. Roadmap

Each milestone ends with something that works.

| # | Milestone | Content |
|---|---|---|
| M0 | Engine goes multiplatform | Typealiases; core targets build for iOS; minimal `UITextView` editor with live styling; iOS demo |
| M1 | WYSIWYG tables (done) | Editable grid on macOS and iOS; write-back; undo; "Edit as Markdown" |
| M2 | Notebook + index | NmwCore: open folder, watch, frontmatter, GRDB index, FTS, links/backlinks, tags |
| M3 | App shell | Three-column UI, note list, create/rename/delete/trash, search, note-link picker |
| M4 | Attachments + previews | Paste/drop/camera, `_attachments/`, `{.size}` attributes on images and links, size menu, link preview cards (web, notes, files) |
| M5 | iCloud | Ubiquity container, placeholders, presenters, conflict merge |
| M6 | nmw server | Go server and protocol, NmwSync server provider, pairing UI |
| M7 | System integration | Spotlight, Share extension, widgets, App Intents, Quick Note |

## 9. Open questions
- Daily notes / templates: v1 or later?
- Apple Pencil drawings: as `.png` attachments with a `.drawing` sidecar, or out of scope?
