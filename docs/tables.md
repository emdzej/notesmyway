# Tables and formulas

## Editing tables

GFM tables render as a grid you can type into. Click a cell to edit it; **Tab** and **Shift-Tab** move between cells, **Return** moves down, and both add a row when you go past the last one. The arrow keys leave the grid above or below it. Right-click a cell for the table commands, including **Edit as Markdown**, which shows the table's source while the caret is in it.

On disk it stays a regular pipe table:

```markdown
| Name   | Kind | Notes          |
| ------ | :--: | -------------- |
| Parser | core | Block + inline |
```

### Markers

Hover over a table (on iPhone and iPad: edit a cell) and its markers appear:

- **Column handles** above each column: insert left or right, move left or right, align left / center / right, fit to content, fit all columns, delete.
- **Row handles** left of each row: insert above or below, move up or down, delete. The header row can't be moved or deleted.
- **+ buttons** on the borders nearest the pointer insert a column or a row right there.
- **Bars** below and to the right of the table add a row or a column at the end.

### Column widths

Columns fit their content by default. Drag a column border to set a width; double-click it to go back to fitting the content. The widths are saved on the line right after the table, in the same `{…}` style as image sizes:

```markdown
| Name | Kind | Notes |
| ---- | ---- | ----- |
| …    | …    | …     |
{cols="30%,auto,120"}
```

`auto` fits the content, a number is a width in points, and `%` is a share of the width available to the table. Cells in a fixed-width column wrap, and their row grows to fit. The line is hidden while the grid is shown. Inserting, moving or deleting columns keeps the widths with their columns.

::: warning Other renderers
Most Markdown renderers show the `{cols=…}` line as a plain line of text under the table. GitHub may show it as an extra row.
:::

Rows have no fixed heights: they size to their content.

## Formulas <span class="nmw-coming">coming</span> {#formulas}

Formulas in tables use the syntax of [vitepress-plugin-markdownformula](https://github.com/emdzej/vitepress-plugin-markdownformula), so a note that computes something in the app shows the same numbers when it's published with VitePress.

A formula is a link whose target is the formula prefixed with `#` — the `#` stands in for Excel's `=`, so the source stays valid Markdown:

```markdown
<!-- table1 -->
| name           | value                |
| -------------- | -------------------- |
| three          | 3                    |
| eight          | 8                    |
| summation      | [?](#SUM(B1:B2))     |
| multiplication | [?](#B1*B2)          |
| average        | [?](#AVERAGE(B1:B2)) |
```

- Each table is a sheet: columns `A`, `B`, …, rows `1`, `2`, …. The header row isn't counted, so the first data row is row 1.
- `<!-- name -->` directly above a table names its sheet; otherwise sheets are `Sheet0`, `Sheet1`, … in document order.
- `table1!C3` reads cell `C3` from the sheet named `table1`.

In the app the cell shows the result, and the formula comes back when you edit the cell.
