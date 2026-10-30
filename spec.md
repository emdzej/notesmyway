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
- Android, Windows, Linux or web clients in v1. The format and sync protocol are specified so these can come later (see §9).
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
    .attachments/               files dropped into notes in Projects/ (default placement)
      sketch.jpg                original file names; " 2", " 3" appended on clashes
  .nmw/
    config.json                 notebook settings (synced)
    trash/                      soft-deleted notes and folders, kept 30 days ("Recently Deleted")
      <unix time> <path, / as " - ">   one item per trashed note or folder
      .index.json               item name → original path (exact restore)
```

**Attachments** are configurable per notebook (Settings window on macOS, "Notebook Settings…" on iOS), stored in `.nmw/config.json`:

| Setting | Default | Options |
|---|---|---|
| Folder name | `.attachments` | any folder name (e.g. `attachments`, `_files`) |
| Location | next to the note: `<note's folder>/<name>/` | in the notebook folder: `<root>/<name>/<note name>/` |
| Show in sidebar | off | on |

```json
{ "attachments": { "folderName": ".attachments", "placement": "nextToNote", "showInSidebar": false },
  "webPreviews": true, "renameFilesToTitle": false }
```

`renameFilesToTitle` (Notebook settings: "Rename files to match the first heading", default off): after the first `#` heading changes and typing pauses ~1.5 s, or when the note is left, the file is renamed to the sanitized heading (`/` `:` `\` → `-`, no leading dots, ≤ 120 characters) through the normal rename + link fix (banner with Undo). Skipped when the name is taken, the heading is empty or starts with "Untitled", or the user undid that rename for that heading. It's a notebook setting so every device renames the same way.

Changing a setting never moves existing files. Keys nmw doesn't know are kept when it saves.

- Any folder can be a notebook. Obsidian vaults open as notebooks, and `.obsidian/` is ignored, but their `[[wikilinks]]` show as plain text (see 3.3).
- Folders are real folders, with unlimited nesting.
- Files and folders starting with `.` are hidden in the UI (and not indexed). The attachment folder shows in the sidebar only when its setting is on.
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
- **Dropped files** go to `.attachments/` next to the file.
- **Sandbox:** opening a file grants access to that file only. Showing sibling images and writing attachments need the folder; nmw asks for it once (a folder picker preselected to the file's folder) and keeps a security-scoped bookmark.
- The window has no sidebar; "Move to Notebook…" copies the file (and the attachments it links to) into a notebook.

### 3.5 Attributes on images and links

A `{…}` block directly after an image or a link carries display attributes. The same size vocabulary applies to both.

```markdown
![Diagram](.attachments/3f2a.jpg){.small}
![](logo.png){.icon}
![](photo.jpg){.large .center}
![](chart.png){width=320}

[Swift Evolution](https://www.swift.org/swift-evolution/){.preview}
[Q3 report](.attachments/Q3.pdf){.preview .large}
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
- **Adding files:** drop any file onto the editor (or paste / camera / scan an image on iOS). nmw copies it to the attachment folder (3.1; default `.attachments/` next to the note; name kept, ` 2`, ` 3` … appended on clashes) and inserts a link at the drop point: `![](…){.medium}` for images, `[name](…)` for other files (add `{.preview}` for a card, 4.4). The engine hands drops to nmw through its `onDropFiles` hook and inserts the returned markdown as one undoable edit.
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

### 4.5 Themes
The theme colors the whole app. The editor (formatted view and viewer) and the markdown source view use all of it. The rest of the app takes three things from it:
- the note list and the note pane: the page `background`;
- the iOS sidebar: a wash of that color (the "My Way" sidebar keeps its gradient);
- the app's accent (tint, selection, checkboxes): `accent`, or `link` if there's no `accent`.

Settings, menus and system sheets stay native.

A theme sets colors for light and dark mode, the body / heading / source fonts, and the code-block highlighting theme (a HighlighterSwift theme name). `modes` (`["light","dark"]` by default) declares which modes it supports. A one-mode theme fixes the app's appearance while it's on, overriding Settings › Appearance, which then reads "Dark (set by theme)". Settings › General › Look picks the theme, and Settings › General › Text picks a font (theme's, System, Serif, Monospaced), the text size, line spacing, and optionally a different theme for the source view. These are device settings (`nmw.theme`, `nmw.editorFont`, `nmw.editorFontSize`, `nmw.editorLineSpacing`, `nmw.sourceTheme`), not synced with notebooks.

Built in: Notes my Way (default), Paper, GitHub, Solarized, Nord, Dracula, Mono. Custom themes are JSON files in the Themes folder: `Application Support/nmw/Themes` on macOS ("Open Themes Folder", "Duplicate as Custom Theme…"), `Files › On My iPhone › Notes my Way › Themes` on iOS. A file whose `id` matches a built-in replaces it.

Installing: `.nmwtheme` (UTType `pl.emdzej.notesmyway.theme`, conforming to `public.json`, exported by the app) opens in the app from Files, Mail, Messages or Finder. Settings › Themes › Install Theme… (`.nmwtheme` or `.json`; drop onto the section on macOS) does the same.
- The file is validated: valid JSON, a `name`, colors that parse, and `modes` that are known. On failure the user sees the reason.
- A clash with an existing id offers Replace or Keep Both ("Name 2", `id-2`).
- Installed themes are written as `<id>.json` into the Themes folder.
- Settings › Themes lists the installed themes with Use / Share (exports a `.nmwtheme`) / Duplicate / Delete. Deleting the current theme falls back to the default.
- `id` defaults to the name made file-safe, and a missing palette is empty.

```json
{
  "id": "harbour",
  "name": "Harbour",
  "font": "serif",
  "headingFont": "system",
  "sourceFont": "Menlo-Regular",
  "codeTheme": { "light": "github", "dark": "github-dark" },
  "light": {
    "background": "#FAFCFD", "text": "#1C2B33", "mutedText": "#6B7C85",
    "heading": "#0B6E8E", "link": "#1A8FA8", "codeBackground": "#EEF4F6",
    "quoteBar": "#C9DCE2", "tableBorder": "#C9DCE2", "tableHeader": "#EEF4F6",
    "selection": "#CDE8EF", "tag": "#1A8FA8",
    "source": { "heading": "#0B6E8E", "code": "#A33A5B", "key": "#9A6A00", "attribute": "#6E57B8" }
  },
  "dark": { "background": "#111A1F", "text": "#DCE6EA", "link": "#5CCFDB" }
}
```

Every color is optional (`#RGB`, `#RRGGBB` or `#RRGGBBAA`); a missing one keeps the default, and a key set in only one palette is used for both. Fonts are `system`, `serif`, `mono`, `rounded` or a PostScript name. Palette keys: `background`, `text`, `mutedText`, `heading`, `headingMarker`, `link`, `accent`, `inlineCode`, `codeBackground`, `quoteBar`, `quoteText`, `rule`, `tableBorder`, `tableHeader`, `selection`, `caret`, `chip` (frontmatter chips), `tag`, `cardBackground`, `cardBorder`, and `source` with `background`, `text`, `marker`, `heading`, `emphasis`, `link`, `url`, `code`, `key`, `attribute`, `listMarker`.

### 4.6 Engine work (in `swift-markdown-engine`)
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

- **Folders:** the notebook's own folder is the top row of the tree, with its subfolders nested under it, all expanded; a folder lists its own notes and those in its subfolders (captioned with the subfolder). The notebook root lists only its own notes (All Notes lists everything).
- **Three columns** (`NavigationSplitView`): sidebar with notebooks, folders, tags, and Pinned / Recent / Trash; note list with title, date, two-line snippet, and thumbnail of the first image; editor. iPhone collapses to a stack.
- **Note list:** sort by modified, created, or title. Pinned notes on top. Swipe actions on iOS: pin, move, delete.
- **New note:** Cmd-N, or a toolbar button that creates `Untitled.md` and focuses it. The file name follows the H1 (debounced) when the notebook's `renameFilesToTitle` is on.
- **Search:** a toolbar search field. FTS over titles and bodies, plus `tag:` and `path:` filters.
- **Quick switcher** (Cmd-O) and **command palette** (Shift-Cmd-P; on iOS also in the notebook menu): fuzzy search over commands (note, folder, format, view, notebook, theme, go-to) and notes, ↑/↓ + Return. "Open File…" is Shift-Cmd-O.
- **Recently Deleted:** a sidebar row (count badge) listing `.nmw/trash`: original path, deletion date, days left. Notes open read-only; Restore (original path, "Name 2" if taken, parents recreated), Delete Now, Empty Trash.
- **Move to Notebook…:** writes the note in the target notebook first, copies the attachments it links to from its attachment folder to the target's attachment location (per that notebook's config) and rewrites those links, then removes the original. Links from other notes in the source notebook aren't rewritten; the user is warned with their count first. The originals of the attachments stay (other notes may use them).
- **Conflicts while editing:** an outside change is adopted silently when the editor has no unsaved text; otherwise a bar offers Keep Mine, Use Disk Version, or Keep Both (saves the other version as `Note (conflict <date>).md`).
- **Panels:** backlinks and outline, as an inspector on macOS and iPad, or a sheet on iPhone.
- **System integration:** Spotlight (CoreSpotlight), a Share extension that appends to Inbox or creates a note, widgets (pinned or recent notes), App Intents / Shortcuts, Quick Note on macOS. See §5.1.
- **Saving:** autosave 500 ms after the last keystroke, with coordinated writes. There is no save button.

### 5.0 Share, print, PDF

- **Rendering:** the engine's `MarkdownHTML.body(for:options:)` turns a note into HTML from the same block and inline parse the editor styles from (no second Markdown parser). Frontmatter becomes chips. `{…}` image sizes and alignment become CSS, `{.preview}` links become cards, and `{cols=…}` becomes `<col>` widths. Formula values come from `MarkdownFormulas.evaluate`. Checklists print boxes, `<!-- -->` lines are dropped, and LaTeX becomes PNG data URIs. Code is highlighted when the app is in light mode.
- **App (`NmwUI/Export/NoteExport.swift`):** the theme's light palette and font become CSS. Images and preview icons are embedded as downsampled data URIs, so the page needs no file access and the PDF stands alone. An offscreen `WKWebView` paginates the page: on iOS through `UIPrintPageRenderer`, on macOS through its `NSPrintOperation` in an offscreen window. Pages are A4, or Letter in the US, Canada and Mexico.
- **Share items:** a temporary `Title.md`, `Title.pdf`, and the plain text. iOS also gets the web view's print formatter, so the share sheet offers Print.

### 5.1 System integration

Extensions can't open notebooks: folder access (security-scoped bookmarks) belongs to the app. They talk to it through the App Group `group.pl.emdzej.notesmyway` (macOS: `A2WT9CD8P3.group.pl.emdzej.notesmyway`, which needs no provisioning profile). The shared formats live in the `NmwShared` package, which has no dependencies.

| Piece | How |
| --- | --- |
| Spotlight | One `CSSearchableItem` per note: title, snippet, text (first 20 000 characters), tags and the notebook name as keywords, modification date. Domain = notebook id, identifier = `<notebook id>/<path>`. The first scan of a notebook indexes everything; afterwards every index change (including the scan's changes on launch) updates or removes items; removing a notebook deletes its domain. Opening a result selects the notebook and the note. |
| Links | `notesmyway://open?notebook=<id>&path=<path>` selects a note; `notesmyway://new?notebook=&folder=&text=` creates one (all optional) and selects it. |
| Shortcuts | App Intents in the app target, running in the app's process: Create Note (title, text, notebook, folder), Append to Note, Open Note, Search Notes (app search syntax, returns notes), Get Note Text. `NoteEntity` (`<notebook id>/<path>`) with title search and recent suggestions; `NotebookEntity`. |
| Widget snapshot | `widgets.json` in the group container: per notebook its name, id, up to 12 pinned and 12 recent notes (title, snippet, path, modified). Written 1 s after the last index change, when it differs; then widget timelines reload. |
| Widgets | Pinned Notes and Recent Notes: small, medium, large; on iOS also Lock Screen rectangular and inline. A note opens with an `open` link; a button makes a new note. They read only the snapshot. |
| Share extension | Text, one web URL, up to 5 images. The user picks a notebook (from the snapshot) and New Note or Add to Inbox (`Inbox.md` at the notebook root, under a date heading), with an optional title and comment. The extension queues `Inbox/<uuid>/job.json` plus image copies in the group container and posts a Darwin notification; the app imports jobs when it becomes active or gets the notification. Web URLs become `[title](url){.preview}`, images are stored as attachments (`![](…){.medium}`). A job stays queued if importing fails. |

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
| M4 | Attachments + previews | Paste/drop/camera, attachment folder settings, `{.size}` attributes on images and links, size menu, link preview cards (web, notes, files) |
| M5 | iCloud | Ubiquity container, placeholders, presenters, conflict merge |
| M6 | nmw server | Go server and protocol, NmwSync server provider, pairing UI |
| M7 | System integration | Spotlight, Share extension, widgets, App Intents, Quick Note |

## 9. Open questions
- Daily notes / templates: v1 or later?
- Plugin ABI for WebAssembly extensions (§9 Later platforms › Plugins).
- Apple Pencil drawings: as `.png` attachments with a `.drawing` sidecar, or out of scope?

## 9. Later platforms (roadmap)

Order, each step building on the previous one:

1. **nmw server** (§7.3) — needed for self-hosted sync anyway.
2. **Web client, served by the server.** TypeScript; editor on CodeMirror 6 with live-preview decorations (Obsidian-style blend editing), table grid widget, `{…}` attributes, frontmatter chips. Formulas evaluated with the same semantics as the Swift engine / vitepress-plugin-markdownformula (shared test corpus: the engine's FormulaTests cases exported as JSON). Themes: the §4.5 JSON schema, mapped to CSS variables. Works on the server's copy of a notebook; offline cache later.
3. **Hosted cloud.** The same server, multi-tenant: accounts (Sign in with Apple / passkeys), quotas, and end-to-end encryption (§7.3 "Later") on by default, so the operator stores ciphertext only.
4. **Windows and Linux desktop.** The web client wrapped in Tauri, with direct file-system access: a local folder is a notebook exactly as on the Mac (same `.nmw/` index-free conventions; the index is rebuilt locally), sync through the server. Not native ports: the Swift engine depends on TextKit 2.
5. **Android** — Tauri mobile or native, decided after 4.

**Plugins (WebAssembly).** Markdown extensions as sandboxed `.wasm` modules, run on Apple platforms by WasmKit (`../WasmKit`, a Swift WebAssembly runtime), and later by the browser's own runtime in the web client. A plugin declares what it contributes in a manifest:
- block or inline syntax: a matcher plus a renderer returning styled ranges or an HTML/image fragment;
- formula functions;
- import/export formats.

The host passes text in and gets styled ranges or HTML back, with no file or network access unless the manifest asks and the user grants it. Plugins install the way themes do: opening a `.nmwplugin` file. Open questions: the ABI (WIT component model vs. a small JSON-over-memory ABI), and the per-keystroke cost of calling into Wasm from the styler (cache results per block).

