# Markdown in the editor

Notes are CommonMark with the GitHub extensions — headings, emphasis, `~~strikethrough~~`, lists, task lists, quotes, code, tables — plus `$…$` / `$$…$$` math and a few additions described below. What you see is rendered, but the file always holds exactly what you typed.

## Blend editing

Formatting renders in place. Markers such as `**`, `_`, `#` and the parts of a link fold away while the caret is elsewhere and come back on the line you're editing, so you can always fix them by hand. Task-list boxes are clickable, code blocks are highlighted, math is typeset, images and preview cards are drawn inline, and tables become an [editable grid](/tables).

Right-click inside text for **Format** (bold, italic), **Heading** (H1–H3) and **Lists**.

## Source mode

**⇧⌘M** — or the `</>` button in the toolbar — switches the open note to Markdown source: every character visible, monospaced, with syntax colours for headings, emphasis markers, code, links, `{…}` attributes and frontmatter keys. Press it again to go back. The selection and the scroll position stay where they were.

To open every note in source mode, set **Settings › General › Notes open as** to **Markdown Source**.

## Frontmatter

A YAML block at the very top of a note holds its properties:

```yaml
---
tags: [project, idea]
pinned: true
created: 2026-10-29
---
```

In the formatted view it collapses into one line of chips: a pin for `pinned: true`, `#tag` chips for the tags, and `key value` chips for everything else. Click the chips, or move the caret into them, to edit the raw lines.

The app never requires frontmatter and only writes keys you change through it (pinning is the only one so far).

## Tags

Tags come from two places, and both count:

- **Inline:** `#idea` anywhere in the text, or nested: `#project/alpha`. A `#` followed only by digits (`#1`) isn't a tag, and nothing inside code counts.
- **Frontmatter:** `tags: [idea, work]`, or one `- idea` per line.

Tags are case-insensitive and listed in the sidebar with their counts.

## Links

Notes link to each other with ordinary Markdown links to relative paths — the same links work on GitHub, in other editors and in static-site generators:

```markdown
[Project idea](Projects/Idea.md)
[See setup](../Guides/Setup%20Guide.md#install)
```

Click a link to open the note (or the file, or the web page). A link to a note that doesn't exist yet offers to create it. **⌘L** inserts a link to a note you pick. When a note is renamed or moved — by the app — every link to it is rewritten.

::: tip Wikilinks
`[[Note]]` and `![[image]]` aren't part of CommonMark, so they show as plain text. Standard links keep the notes portable.
:::

## Attributes

A `{…}` block right after an image or a link sets how it's shown, in the [Pandoc / markdown-it-attrs](https://github.com/arve0/markdown-it-attrs) style. The block is hidden while the caret is elsewhere.

```markdown
![Sketch](.attachments/sketch.jpg){.medium .center}
[Swift](https://swift.org){.preview .small}
```

| Attribute | Images | Links |
|---|---|---|
| `.icon` | small, inline with the text | the site icon only |
| `.small` `.medium` `.large` | fixed sizes | card sizes |
| `.full` | the full width of the note | — |
| `.left` `.center` `.right` | alignment | alignment |
| `width=320` `height=200` | exact size in points | — |
| `.preview` | — | show as a preview card |

Obsidian's `![alt|200](image.png)` width hint is understood too.

A preview card shows a web page's title, description and image, a note's title and first lines, or a file's thumbnail, kind and size. Web pages are only fetched for links marked `.preview`, and only when **Load previews for web links** is on for the notebook.

### Setting them without typing

- **Right-click** an image for **Image Size** and **Align**; a link for **Show as Preview Card**; a card for **Card Size**, **Align** and **Show as Link**.
- **The marker bar** appears when the caret is in an image or a link: S / M / L / full width and alignment for images, sizes and **back to link** for cards. On the Mac, resting the pointer on a plain link shows a **Preview Card** button.
- **The Format menu** has the same commands for the image or link at the caret; **⇧⌘K** turns a link into a card.

Every change is a single undo step and keeps any other attributes in the block.
