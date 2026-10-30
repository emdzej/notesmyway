# Third-party notices

Notes my Way includes the open-source software below. The app shows the same list, with each licence's
full text, in **Settings › About** (the text files are in
`apple/Packages/NmwUI/Sources/NmwUI/Resources/Acknowledgements/`).

| Component | Used for | Licence | Copyright |
| --- | --- | --- | --- |
| [MarkdownKit](https://github.com/emdzej/markdownkit) | The editor | Apache 2.0 | 2026 Michał Jaskólski |
| [swift-markdown-engine](https://github.com/nodes-app/swift-markdown-engine) | What MarkdownKit is derived from (see its NOTICE) | Apache 2.0 | 2026 Luca Chen and contributors |
| [GRDB](https://github.com/groue/GRDB.swift) | The SQLite index | MIT | 2015-2025 Gwendal Roué |
| [HighlighterSwift](https://github.com/smittytone/HighlighterSwift) | Code highlighting | MIT | 2026 Tony Smith; portions 2016 Juan Pablo Illanes |
| [highlight.js](https://highlightjs.org) (inside HighlighterSwift) | Code highlighting | BSD 3-Clause | 2006-2026 Josh Goebel and contributors |
| [SwiftMath](https://github.com/mgriebling/SwiftMath) | LaTeX formulas | MIT | 2023 Computer Inspirations |
| SwiftMath's math fonts (STIX, Latin Modern and others) | LaTeX formulas | SIL Open Font License, GUST Font License | their authors |

When adding a dependency, add its licence file to that folder, add an entry to `Acknowledgement.all` in
`Views/AboutView.swift`, and add a row here.
