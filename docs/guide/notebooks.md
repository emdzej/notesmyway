# Notebooks and folders

## Several notebooks

Add as many notebooks as you like and switch between them from the menu at the top of the sidebar. **Remove “…” from Notes my Way** in the same menu only forgets the notebook; the folder and its files stay where they are.

The app watches the folder, so a note edited in another app — or synced from another device — shows up right away. Notebook settings and the trash live in a hidden `.nmw/` folder inside the notebook, so they travel with it.

## Folders

The sidebar shows the notebook's folder with its subfolders nested under it. Selecting a folder lists its notes and the notes of its subfolders; a caption shows which subfolder a note is in. To show or hide a folder's subfolders, use the arrow next to it (on iPhone and iPad, the chevron at the right of the row; tapping the folder's name opens it).

- **New folder:** right-click (long-press on iPhone and iPad) a folder › **New Folder**.
- **Rename:** **Rename…** — every link that points into the folder is updated.
- **Delete:** **Move to Trash…**, or the **Delete** key on the Mac; the app asks first.

Folders and files whose names start with `.` are hidden.

## Notes

Right-click (or long-press) a note in the list:

- **Pin / Unpin:** pinned notes are listed first and gathered under **Pinned**. Pinning writes `pinned: true` into the note's [frontmatter](/guide/writing#frontmatter), so it syncs with the file.
- **Rename…:** renames the file and updates every link to it.
- **Move To:** moves it to another folder, again updating links.
- **Move to Trash:** the **Delete** key on the Mac; on iPhone and iPad, swipe left. Swipe right to pin. It goes to [Recently Deleted](#recently-deleted).
- **File names from headings:** with **Rename files to match the first heading** on (notebook settings), a note's file is renamed after its first `# heading` when you pause typing or leave the note. Links to it are updated, and the banner offers **Undo**.

After a rename or a move, a banner says how many notes had their links updated, with an **Undo**.

<div class="nmw-shot">
  <img src="/screenshots/ipad-lisbon-dark.webp" alt="iPad in dark mode: notebook with folders, tags and a travel note" />
</div>

## Search

The search field above the note list filters as you type. It matches every word you type by prefix, ignoring case and accents. Two filters narrow it down: `tag:baking` (or `#baking`) and `path:Projects/`.

## Quick switcher, command palette, outline and backlinks

- **⌘O** opens a quick switcher: type part of a note's name to jump to it.
- **⇧⌘P** opens the **command palette** (on iPhone and iPad also from the notebook menu, **Command Palette…**). Type a few letters of any command or note: new note or folder, pin, rename, move to a folder or another notebook, move to trash, formatting, Markdown source, the outline, switching notebooks or themes, going to a folder or tag. **↑** / **↓** pick, **Return** runs it.
- **⌥⌘I**, or the inspector button, shows the note's **outline** (tap a heading to jump there) and its **backlinks**, the notes that link to it.

## Recently Deleted

Deleted notes and folders go to **Recently Deleted** at the bottom of the sidebar, and are kept there for 30 days. Each item shows where it was and how many days it has left.

- **See a deleted note:** select it; it opens read-only.
- **Restore:** the **Restore** button, the context menu, or on iPhone and iPad a swipe right. The note or folder goes back to where it was, recreating its folder if needed. If something with the same name is there now, it comes back as "Name 2".
- **Delete Now:** the context menu, a swipe left, or the **Delete** key on the Mac. This can't be undone.
- **Empty Trash:** in the toolbar of Recently Deleted.

On disk, Recently Deleted is the notebook's hidden `.nmw/trash/` folder.

## Move to another notebook

**Move to Notebook…** (context menu of a note, or the command palette) moves a note into another notebook in the app, with the images and files it uses from its attachment folder. They're copied to the other notebook's attachment folder, following its settings, and the note's links to them are updated.

If other notes in the current notebook link to the note, the app tells you how many first: those links will stop working, because they point into a notebook the note has left.

## Share, print and PDF

**Share** sends a note as a Markdown file and as plain text. The app receiving it picks what it understands: Mail attaches the file, Messages takes the text, Files and AirDrop get the `.md`. For a PDF, print the note: on the Mac the print dialog's **PDF** menu saves one (or use **File › Export as PDF…**), and on iPhone and iPad **Print** in the share sheet can save or share a PDF.

- **iPhone and iPad:** the Share button at the top of a note. The share sheet also has **Print**. With a keyboard, ⌘P prints straight away.
- **Mac:** the Share button in the note's toolbar, or **File › Share…**. **File › Print…** (⌘P) prints, and **File › Export as PDF…** saves a PDF where you choose.
- **From the note list:** right-click (or touch and hold) a note › **Share…**, without opening it.
- **Command palette:** Share…, Print… and, on the Mac, Export as PDF….

The printed page looks like the formatted note, on a white page in your theme's light colors and font. Frontmatter prints as a line of chips (pinned, tags). Images print at their `{.small}` / `{.medium}` / `{.large}` sizes and alignment. Tables print with their column widths, formula cells show their values, and checklists show their boxes with checked items struck through. `{.preview}` links print as cards when their preview is loaded. `<!-- -->` lines don't print. Pages are A4, or Letter where that's the local paper size.

## Import from Apple Notes (Mac)

**File › Import from Apple Notes…** copies your Apple Notes into a folder of the current notebook, one Markdown file per note. Apple Notes isn't changed.

1. Notes my Way asks for access to Apple Notes' data folder, `group.com.apple.notes`. The window that opens has it selected already, so click **Open**.
2. It shows how many notes it found. Pick the folder name ("Apple Notes" by default) and click **Import**.

Notes keep their folders, their creation and modification dates, and whether they're pinned. Their first line becomes the title. Headings, bold, italic, strikethrough, links, bulleted and numbered lists, checklists, quotes, monospaced blocks and tables become Markdown. A table's first row becomes its header, since Markdown tables need one. Photos, files, drawings and scans are copied into the attachment folder. Tags stay `#tags`, and links between notes point at the imported files.

A few things don't come across yet:

- **Locked notes** are skipped. Unlock them in Apple Notes first to import them.
- **A table that can't be read** is left out, and a line in the note marks where it was.
- **Attachments that are only in iCloud** can't be found until Apple Notes has downloaded them. Open those notes in Apple Notes, then import again.
- **Recently Deleted** isn't imported.

## Changes made elsewhere

If a note changes on disk while you have unsaved edits — another app, another device — a bar above it offers **Keep Mine**, **Use Disk Version** or **Keep Both**, which saves your version as a separate `(conflict …)` copy. Without unsaved edits, the new version is simply loaded.
