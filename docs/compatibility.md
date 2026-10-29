# Files and compatibility

Notes my Way doesn't have a file format of its own. A notebook looks like this:

```
<notebook>/
  Inbox.md
  Projects/
    Idea.md
    .attachments/          files dropped into notes in Projects/
      sketch.jpg
  .nmw/
    config.json            notebook settings
    trash/                 notes moved to the trash, kept 30 days
```

- **Encoding:** UTF-8. A byte-order mark is kept if the file has one. Files that aren't UTF-8 open read-only.
- **Line endings:** kept as they are (CRLF files stay CRLF); new files use `\n`.
- **Saving:** coordinated, atomic writes. A file changed on disk is never overwritten silently.
- **The index:** an SQLite database in the app's own storage, not in the notebook. It only holds what can be rebuilt from the files.
- **Hidden things:** files and folders starting with `.` aren't shown or indexed.

## Other apps

**Obsidian.** A vault opens as a notebook; `.obsidian/` is ignored. Frontmatter, `#tags`, nested tags, `$math$` and the `![alt|200](…)` width hint work as in Obsidian. `[[wikilinks]]` show as plain text: Notes my Way uses standard relative links instead.

**GitHub, VS Code, static-site generators.** Notes are CommonMark + GFM, and links between notes are relative paths, so they work there as written. `{…}` attributes after images and links follow the Pandoc / kramdown / markdown-it-attrs convention; renderers without it show the braces as text, and the link still works.

**VitePress.** With [markdown-it-attrs](https://github.com/arve0/markdown-it-attrs) for the attributes and [vitepress-plugin-markdownformula](https://github.com/emdzej/vitepress-plugin-markdownformula) for table formulas, a notebook can be published as a site that matches what you see in the app.

**Sync tools.** Because a notebook is a folder, Dropbox, Syncthing, iCloud Drive or git keep it in sync today; the app picks up their changes as they arrive. Built-in iCloud and self-hosted sync are on the [roadmap](/backlog).
