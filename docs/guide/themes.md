# Themes and appearance

<div class="nmw-shot">
  <img src="/screenshots/ipad-paper.webp" alt="iPad: the Paper theme with a serif note and the My Way sidebar" />
</div>

## Look

**Settings › General › Look** has:

- **Theme**: it colors the whole app, not just the editor. You get the note page, the note list, a wash over the iPhone and iPad sidebar, and the accent (buttons, selection, checkboxes), which is the theme's link color.
- **Appearance**: System, Light or Dark. A theme made for only one mode switches the app to that mode while it's on, and Appearance then shows "Dark (set by theme)" or "Light (set by theme)".
- **Sidebar**: **From Theme** (the default), **System Default**, or **My Way**, the icon's teal-to-navy gradient with light text. From Theme uses the theme's own sidebar gradient if it has one (Notes my Way's is the My Way gradient), and otherwise a wash of its page color.

Settings windows, menus and the share sheet keep the system look.

## Built-in themes

Notes my Way comes with built-in themes for the formatted editor, the Markdown source view and code blocks. Each has a light and a dark variant.

| Theme | Look |
| --- | --- |
| Notes my Way | The default: system font, the app's teal accent |
| Paper | Serif (New York) on a warm page |
| GitHub | The colours of GitHub's Markdown |
| Solarized | Ethan Schoonover's palette |
| Nord | Cool arctic blues |
| Dracula | Dark-leaning, vivid accents |
| Mono | Typewriter: monospaced throughout |

## Text

In **Settings › General › Text**:

- **Font**: the theme's font, or System, Serif or Mono.
- **Text size** and **Line spacing**.
- **Markdown source theme**: the same as the editor, or a different theme for source mode (⇧⌘M) and code blocks.

Table headers use a light tint of the theme's accent unless the theme sets its own `tableHeader` color.

## Installing themes

A theme travels as a `.nmwtheme` file, which is JSON inside.

- **Open the file**: tap it in Files, Mail or Messages, or double-click it in Finder. Notes my Way checks it and asks whether to **Install and Use** it or just **Install** it.
- **Settings › General › Themes › Install Theme…** picks a `.nmwtheme` or `.json` file. On the Mac you can also drop a file onto the Themes section.
- **If a theme with the same id already exists** (built-in or installed), choose **Replace** or **Keep Both**. Keep Both installs it as "Name 2".
- **If the file has a problem**, the app says what's wrong, for example "These colors aren't hex colors like #1A8FA8: light.link."

Installed themes are listed under **Themes**, each with a menu: **Use**, **Share…** (sends the `.nmwtheme` file), **Duplicate** and **Delete**. **Duplicate** and **Share** also work on the current theme, built-ins included.

## Your own themes

A theme is a JSON file in the Themes folder:

- **Mac**: **Settings › General › Themes › Open Themes Folder**. **Duplicate** writes the current theme there as a starting point, and **Reload** picks up your edits.
- **iPhone and iPad**: the app's `Themes` folder in the Files app (On My iPhone › Notes my Way).

A file whose `id` matches a built-in theme replaces it.

```json
{
  "id": "harbor",
  "name": "Harbor",
  "font": "serif",
  "sourceFont": "mono",
  "codeTheme": { "light": "atom-one-light", "dark": "atom-one-dark" },
  "modes": ["light", "dark"],
  "light": {
    "background": "#FBFAF7",
    "text": "#1D2B33",
    "heading": "#0B4F6C",
    "link": "#1A8FA8",
    "tableHeader": "#1A8FA820",
    "source": { "key": "#B5651D", "attribute": "#7A4FB5" }
  },
  "dark": {
    "background": "#12191D",
    "text": "#DDE6EA",
    "link": "#5CCFDB"
  }
}
```

- **`name`** is required. **`id`** defaults to the name, lowercased with dashes.
- **`sidebar`**: the sidebar's colors from top to bottom, for example `["#148093", "#0A345C"]`. One color gives a solid fill. Sidebar text turns light on it. Leave it out to get a wash of the page color.
- **`modes`**: `["light", "dark"]` (the default when it's missing), `["light"]` or `["dark"]`. With one mode, only that palette is needed, and the app switches to that mode while the theme is on.
- **Colors**: `#RGB`, `#RRGGBB` or `#RRGGBBAA`. Every key is optional; a key set in only one palette is used for both.
- **Palette keys**: `background`, `text`, `mutedText`, `heading`, `headingMarker`, `link`, `accent` (the app's accent; it defaults to `link`), `inlineCode`, `codeBackground`, `quoteBar`, `quoteText`, `rule`, `tableBorder`, `tableHeader`, `selection`, `caret`, `chip`, `tag`, `cardBackground`, `cardBorder`.
- **`source` keys** (source mode): `background`, `text`, `marker`, `heading`, `emphasis`, `link`, `url`, `code`, `key`, `attribute`, `listMarker`.
- **Fonts**: `system`, `serif`, `mono`, `rounded`, or a PostScript font name.
