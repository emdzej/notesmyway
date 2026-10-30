# Roadmap

What's done, and what comes next. Dates aren't promised.

## Done

- Notebooks from any folder, nested folders, tags, pinned notes, full-text search, backlinks, outline.
- Rename and move with automatic link fixing and undo; trash kept 30 days.
- Blend editing, source mode, frontmatter chips, code highlighting, math.
- Attachments with per-notebook settings; image sizes and alignment; link preview cards for web pages, notes and files.
- Editable table grid with markers, handles and column widths.
- Standalone `.md` files; Mac, iPhone and iPad.
- Formulas in tables, compatible with [vitepress-plugin-markdownformula](https://github.com/emdzej/vitepress-plugin-markdownformula).
- Themes: built-in themes for the editor, source view and code, and JSON themes of your own.
- Import from Apple Notes on the Mac: folders, dates, pinned notes, formatting, checklists and attachments.
- A formatting bar above the keyboard on iPhone and iPad (with formula buttons in table cells), and a Format menu with Apple Notes' shortcuts on the Mac.

## Next

- **Apple Notes tables** — convert tables during the import, too.
- **iCloud sync** — notebooks in iCloud Drive, with conflict merging.
- **Self-hosted sync** — a small Go server with device pairing, for people who'd rather not use iCloud.
- **System integration** — Spotlight, a Share extension, widgets, Shortcuts and Quick Note.
- Smaller things: a command palette, find and replace, restoring from the trash, Move to Notebook…, an option to rename files after their first heading.

## Later

- **Web app, self-hosted** — the same notebooks in a browser, served by the self-hosted sync server: plain files, the same Markdown features (blend editing, tables, formulas, themes), working against the server's copy.
- **Web app in the cloud** — a hosted version of the same server for people who don't want to run one, with accounts and end-to-end encryption, so notes stay unreadable to whoever runs it.
- **Windows and Linux** — desktop apps built on the web app's editor, opening local folders as notebooks just like the Mac app, and syncing through the server.
- **Android** — after the desktop apps, on the same foundation.
- **Plugins in WebAssembly** — Markdown extensions (new block and inline syntax, custom renderers, formula functions, import/export formats) as sandboxed `.wasm` modules run by WasmKit, a WebAssembly runtime written in Swift. Plugins could be shared like themes and installed by opening a file. Because they are WebAssembly, the same plugins could later run in the web app and on Windows and Linux.
- **Theme gallery** — themes on this site with an Install button that opens the app (`notesmyway://theme?url=…`).

