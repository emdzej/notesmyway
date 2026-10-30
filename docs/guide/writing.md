# Writing

Notes are CommonMark with the GitHub extensions — headings, emphasis, `~~strikethrough~~`, lists, checklists, quotes, code, tables — plus `$…$` / `$$…$$` math. What you see is formatted, but the file always holds exactly what you typed.

## Formatting in place

Markers such as `**`, `_`, `#` and the parts of a link fold away while the caret is elsewhere and come back on the line you're editing, so you can always fix them by hand. Checklist boxes are tappable, code blocks are highlighted, math is typeset, and images and preview cards are drawn inline.

<div class="nmw-shot-row">
  <img src="/screenshots/iphone-welcome.webp" alt="iPhone: a note with properties, a checklist and a quote" />
  <img src="/screenshots/iphone-note-dark.webp" alt="iPhone in dark mode: a note with a photo and lists" />
</div>

## The formatting bar (iPhone and iPad)

While you edit, a bar floats above the keyboard:

- **Aa:** Title, Heading, Subheading and Body; bold, italic, strikethrough and code; bulleted, numbered and checklist lists, quote, and indent.
- **Checklist:** turns the current line, or every selected line, into a checklist item.
- **Table:** inserts an empty table.
- **Paperclip:** adds a photo from your library or any file. It's copied into the note's [attachments folder](/guide/images#attachments).
- **Keyboard:** hides the keyboard.

In a table cell the bar changes: it shows the cell's address (such as `B3`) and buttons for `=`, common functions and `:`. See [formulas](/guide/tables#formulas).

## The formatting toolbar (Mac)

The note's toolbar has the same controls as the bar on iPhone and iPad:

- **Aa** opens the text styles: Title, Heading, Subheading and Body; bold, italic, strikethrough and code; bulleted, numbered and checklist items, quotes, and indent.
- **Checklist** turns the line into a checklist item. Its arrow has **Mark as Checked**, **Check All**, **Uncheck All**, **Move Checked to Bottom** and **Delete Checked**.
- **Table** inserts a table, and the **paperclip** attaches files, which are stored with the note like dropped ones.

## The Format menu (Mac)

The same commands, with the shortcuts Apple Notes uses. They're also in the command palette (**⇧⌘P**): type "bold", "check", "table"…

| Command | Shortcut |
| --- | --- |
| Title / Heading / Subheading / Body | ⇧⌘T / ⇧⌘H / ⇧⌘J / ⇧⌘B |
| Bold / Italic / Strikethrough / Code | ⌘B / ⌘I / ⇧⌘X / ⌘E |
| Checklist / Bulleted / Numbered list | ⇧⌘L / ⇧⌘7 / ⇧⌘9 |
| Quote / Indent / Outdent | ⌘' / ⌘] / ⌘[ |
| Table | ⌥⌘T |

Right-clicking text offers Format, Heading and Lists too.

## Markdown source

**⇧⌘M** — or the `</>` button in the toolbar — switches the open note to its Markdown source: every character visible, monospaced, with colours for headings, emphasis markers, code, links, `{…}` attributes and frontmatter keys. Press it again to go back; the selection and the scroll position stay put. To open every note this way, set **Settings › General › Notes open as** to **Markdown Source**.

<div class="nmw-shot">
  <img src="/screenshots/ipad-source.webp" alt="iPad: a note shown as Markdown source with syntax colours" />
</div>

## Frontmatter

A YAML block at the very top of a note holds its properties:

```yaml
---
tags: [baking, recipes]
pinned: true
---
```

In the formatted view it collapses into one line of chips: a pin for `pinned: true`, a chip per tag, and `key value` chips for everything else. Tap the chips, or move the caret into them, to edit the lines. Frontmatter is optional; the app only writes the keys you change through it.

## Tags

Tags come from two places, and both count:

- **In the text:** `#idea` anywhere, or nested: `#project/alpha`. A `#` followed only by digits (`#1`) isn't a tag, and nothing inside code counts.
- **In the frontmatter:** `tags: [idea, work]`, or one `- idea` per line.

The sidebar lists every tag with its count; select one to see its notes.

## Links between notes

Notes link to each other with ordinary Markdown links to relative paths, so the links work in other editors and on published sites too:

```markdown
[Kitchen budget](Projects/Kitchen%20budget.md)
```

Tap a link to open the note, file or web page. A link to a note that doesn't exist yet offers to create it. **⌘L** (Link to Note…) inserts a link to a note you pick. When you rename or move a note in the app, every link to it is rewritten.

::: tip Wikilinks
`[[Note]]` isn't part of CommonMark, so it shows as plain text. Standard links keep notes portable.
:::
