# User guide

## Notebooks

A **notebook** is any folder of Markdown files. Add one with **Open a Folder as Notebook…** on the welcome screen, or **File › Add Notebook…** later. On iPhone and iPad you pick the folder in the Files picker — iCloud Drive, On My iPhone, or a provider like Dropbox.

You can add several notebooks and switch between them from the menu at the top of the sidebar. **Remove “…” from Notes my Way** in the same menu only forgets the notebook; the folder and its files stay where they are.

The first time a notebook opens, the app reads every note and builds its index. After that it only re-reads files whose size or modification date changed, and it watches the folder, so edits made in other apps show up right away.

Notebook settings and the trash live in a hidden `.nmw/` folder inside the notebook, so they travel with it.

### Folders

The sidebar shows the notebook's folder with its subfolders nested under it. Selecting a folder lists its notes and the notes of its subfolders; a caption shows which subfolder a note is in.

Right-click a folder for **New Folder**, **Rename…** and **Move to Trash…**. Renaming a folder updates every link that points into it.

Folders and files whose names start with `.` are hidden and not indexed.

### All Notes, Pinned and Tags

**All Notes** lists every note in the notebook, **Pinned** the pinned ones. The **Tags** section lists every tag with its count; nested tags such as `#project/alpha` are counted under their parents too. Pinned notes are always listed first.

### Search

The search field filters the current list as you type. It matches all words, by prefix, ignoring case and diacritics. Two filters narrow it down: `tag:idea` (or `#idea`) and `path:Projects/`.

## Notes

**⌘N** (or the compose button) creates `Untitled.md` in the selected folder; the next one is `Untitled 2.md`. The title shown in the list is the first `# heading`, or the file name when there isn't one.

Right-click a note in the list for:

- **Pin / Unpin** — writes `pinned: true` into the note's frontmatter, so it syncs with the file.
- **Rename…** — renames the file and updates every link to it.
- **Move To** — moves it to another folder, again updating links.
- **Move to Trash** — moves it to `.nmw/trash/`. Trashed notes are kept for 30 days. The **Delete** key does the same for the selected note; on a folder it asks first.

On iPhone and iPad, swipe a note left to trash it and right to pin it.

After a rename or a move, a banner says how many notes had their links updated, with an **Undo** that moves the file back and restores the links.

### Changes from other apps

Notes are saved half a second after you stop typing. If the file changes on disk while you have unsaved edits — another app, another device — a bar offers **Keep Mine**, **Use Disk Version** or **Keep Both** (which saves your version as a `(conflict …)` copy). Without unsaved edits, the outside change is simply loaded.

### Outline and backlinks

**⌥⌘I** opens the inspector: the note's outline (click a heading to jump to it) and the notes linking to this one.

### Quick switcher and note links

**⌘O** opens a fuzzy note switcher. **⌘L** (Link to Note…) picks a note and inserts a relative link to it at the caret.

## Attachments

Drop or paste a file into a note and the app copies it into the notebook and inserts a link — `![](…){.medium}` for images, a plain link for anything else. Original file names are kept; clashes get " 2", " 3". Dropping the same file twice reuses the first copy.

Where files go is a notebook setting (**Settings › Notebook**):

| Setting | Default | Options |
|---|---|---|
| Folder name | `.attachments` | any folder name, such as `attachments` or `_files` |
| Location | next to the note: `<note's folder>/<name>/` | in the notebook folder: `<notebook>/<name>/<note name>/` |
| Show in sidebar | off | on |

Changing these never moves files that are already there.

## Standalone files

Notes my Way also opens a single `.md` file that isn't in a notebook — from Finder's **Open With**, a double-click once it's the default app, **File › Open File… (⇧⌘O)**, or the Files app on iOS. If the file is inside a notebook you've added, it opens in that notebook. Otherwise it opens in its own window (a sheet on iOS) with the same editor, autosave and conflict handling.

Because the app is sandboxed, images and attachments next to a standalone file need access to its folder; a bar above the note asks for it once and remembers the answer.

## Settings

**Settings (⌘,)** on the Mac; on iPhone and iPad, **Settings…** in the notebook menu.

**General** applies to the app on this device:

- **Appearance** — System, Light or Dark.
- **Sidebar** — System Default, or **My Way**: the icon's teal-to-navy gradient with light text.
- **Notes open as** — Formatted or Markdown Source.
- **Markdown Files** (Mac) — which app opens `.md` files, and a button to make it this one.

**Notebook** is saved in the notebook's `.nmw/config.json`, so it syncs with the notebook: the attachment settings above, and **Load previews for web links** (only links marked `{.preview}` are ever fetched).

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘N | New note |
| ⌘O | Open quickly (note switcher) |
| ⇧⌘O | Open a Markdown file |
| ⌘L | Link to note |
| ⇧⌘M | Switch between formatted and Markdown source |
| ⇧⌘K | Show the link at the caret as a preview card |
| ⌥⌘I | Outline and backlinks |
| ⌫ | Move the selected note or folder to the trash |
| ⌘, | Settings |
