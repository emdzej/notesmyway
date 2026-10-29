# Images, attachments and previews

## Attachments

Drop, paste or attach a file — on iPhone and iPad with the paperclip in the formatting bar — and the app copies it into the notebook and inserts a link: an image is shown inline, other files as a link. Original file names are kept; clashes get " 2", " 3".

Where files go is a notebook setting, **Settings › Notebook**:

| Setting | Default | Options |
| --- | --- | --- |
| Folder name | `.attachments` | any name, such as `attachments` or `_files` |
| Location | next to the note: `<note's folder>/<name>/` | in the notebook: `<notebook>/<name>/<note name>/` |
| Show in sidebar | off | on |

Changing these never moves files that are already there.

<div class="nmw-shot-row">
  <img src="/screenshots/iphone-note.webp" alt="iPhone: a recipe with a photo and an ingredients table" />
  <img src="/screenshots/iphone-lisbon.webp" alt="iPhone: a travel note with a large photo" />
</div>

## Image sizes and alignment

A `{…}` block right after an image sets how it's shown. It's hidden while the caret is elsewhere.

```markdown
![Focaccia](.attachments/focaccia.jpg){.medium .center}
```

| Attribute | Effect |
| --- | --- |
| `.icon` | small, inline with the text |
| `.small` `.medium` `.large` | fixed sizes |
| `.full` | the full width of the note |
| `.left` `.center` `.right` | alignment |
| `width=320` `height=200` | exact size in points |

You don't have to type them:

- **The marker bar:** with the caret in an image, a small bar offers S, M, L and full width, and alignment.
- **The menus:** right-click an image for **Image Size** and **Align**; on the Mac the **Format** menu has them too.

Every change is one undo step and keeps any other attributes in the block.

## Preview cards

Add `.preview` after a link and it's drawn as a card: a web page's title, description and image, a note's title and first lines, or a file's thumbnail, kind and size.

```markdown
[Kitchen budget](Projects/Kitchen%20budget.md){.preview}
[Swift](https://swift.org){.preview .small}
```

Right-click a link for **Show as Preview Card** (on the Mac also **⇧⌘K**); a card has **Card Size**, **Align** and **Show as Link**. On the Mac, resting the pointer on a plain link shows a **Preview Card** button.

Web pages are only fetched for links marked `.preview`, and only while **Load previews for web links** is on for the notebook.
