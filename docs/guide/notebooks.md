# Notebooks and folders

## Several notebooks

Add as many notebooks as you like and switch between them from the menu at the top of the sidebar. **Remove “…” from Notes my Way** in the same menu only forgets the notebook; the folder and its files stay where they are.

The app watches the folder, so a note edited in another app — or synced from another device — shows up right away. Notebook settings and the trash live in a hidden `.nmw/` folder inside the notebook, so they travel with it.

## Folders

The sidebar shows the notebook's folder with its subfolders nested under it. Selecting a folder lists its notes and the notes of its subfolders; a caption shows which subfolder a note is in.

- **New folder:** right-click (long-press on iPhone and iPad) a folder › **New Folder**.
- **Rename:** **Rename…** — every link that points into the folder is updated.
- **Delete:** **Move to Trash…**, or the **Delete** key on the Mac; the app asks first.

Folders and files whose names start with `.` are hidden.

## Notes

Right-click (or long-press) a note in the list:

- **Pin / Unpin:** pinned notes are listed first and gathered under **Pinned**. Pinning writes `pinned: true` into the note's [frontmatter](/guide/writing#frontmatter), so it syncs with the file.
- **Rename…:** renames the file and updates every link to it.
- **Move To:** moves it to another folder, again updating links.
- **Move to Trash:** the **Delete** key on the Mac; on iPhone and iPad, swipe left. Swipe right to pin.

After a rename or a move, a banner says how many notes had their links updated, with an **Undo**.

<div class="nmw-shot">
  <img src="/screenshots/ipad-lisbon-dark.webp" alt="iPad in dark mode: notebook with folders, tags and a travel note" />
</div>

## Search

The search field above the note list filters as you type. It matches every word you type by prefix, ignoring case and accents. Two filters narrow it down: `tag:baking` (or `#baking`) and `path:Projects/`.

## Quick switcher, outline and backlinks

- **⌘O** opens a quick switcher: type part of a note's name to jump to it.
- **⌥⌘I**, or the inspector button, shows the note's **outline** (tap a heading to jump there) and its **backlinks**, the notes that link to it.

## Trash

Trashed notes and folders go to the notebook's `.nmw/trash/` folder and are kept there for 30 days. To get one back before then, move it out of that folder in Finder or Files.

## Changes made elsewhere

If a note changes on disk while you have unsaved edits — another app, another device — a bar above it offers **Keep Mine**, **Use Disk Version** or **Keep Both**, which saves your version as a separate `(conflict …)` copy. Without unsaved edits, the new version is simply loaded.
