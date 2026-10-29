# Themes and appearance

<div class="nmw-shot">
  <img src="/screenshots/ipad-paper.webp" alt="iPad: the Paper theme with a serif note and the My Way sidebar" />
</div>

## Appearance and sidebar

**Settings › General** has **Appearance** — System, Light or Dark — and **Sidebar**: System Default, or **My Way**, the icon's teal-to-navy gradient with light text.

## Editor themes

Notes my Way comes with built-in themes for the formatted editor, the Markdown source view and code blocks. Each has a light and a dark variant that follows **Settings › General › Appearance**.

| Theme | Look |
| --- | --- |
| Notes my Way | The default: system font, the app's teal accent |
| Paper | Serif (New York) on a warm page |
| GitHub | The colours of GitHub's Markdown |
| Solarized | Ethan Schoonover's palette |
| Nord | Cool arctic blues |
| Dracula | Dark-leaning, vivid accents |
| Mono | Typewriter: monospaced throughout |

## Settings

In **Settings › General › Theme**:

- **Theme**: the formatted view's theme, with a preview swatch.
- **Font**: the theme's font, or System, Serif or Mono.
- **Text size** and **Line spacing**.
- **Markdown source theme**: the same as the editor, or a different theme for source mode (⇧⌘M) and code blocks.

Table headers use a light tint of the theme's accent unless the theme sets its own `tableHeader` color.

## Your own themes

A theme is a JSON file in the Themes folder:

- **Mac**: **Settings › General › Theme › Open Themes Folder**. **Duplicate as Custom Theme…** writes the current theme there as a starting point; **Reload** picks up edits.
- **iPhone and iPad**: the app's `Themes` folder in the Files app (On My iPhone › Notes my Way).

A file whose `id` matches a built-in theme replaces it.

```json
{
  "id": "harbor",
  "name": "Harbor",
  "font": "serif",
  "sourceFont": "mono",
  "codeTheme": { "light": "atom-one-light", "dark": "atom-one-dark" },
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

- **Colors**: `#RGB`, `#RRGGBB` or `#RRGGBBAA`. Every key is optional; a key set in only one palette is used for both.
- **Palette keys**: `background`, `text`, `mutedText`, `heading`, `headingMarker`, `link`, `inlineCode`, `codeBackground`, `quoteBar`, `quoteText`, `rule`, `tableBorder`, `tableHeader`, `selection`, `caret`, `chip`, `tag`, `cardBackground`, `cardBorder`.
- **`source` keys** (source mode): `background`, `text`, `marker`, `heading`, `emphasis`, `link`, `url`, `code`, `key`, `attribute`, `listMarker`.
- **Fonts**: `system`, `serif`, `mono`, `rounded`, or a PostScript font name.
