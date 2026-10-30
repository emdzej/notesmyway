# Notes my Way

A notes app for macOS, iOS and iPadOS that feels like Apple Notes and keeps every note as a plain
Markdown file in a folder you choose. Formatting renders in place and the markers come back on the
line you're editing; tables are an editable grid with formulas; themes color the whole app.

- **Site and user guide:** <https://notesmyway.emdzej.pl> (built from `docs/`)
- **Design:** [`spec.md`](spec.md). **Progress:** [`status.md`](status.md). **Roadmap:** [`docs/backlog.md`](docs/backlog.md).
- **Notes for coding agents:** [`AGENTS.md`](AGENTS.md).

## How it works

A notebook is any folder of `.md` files: folders are real folders, attachments are files next to the
notes. A small SQLite index (GRDB) in Application Support holds search, tags, backlinks and task
counts, and only what can be rebuilt from the files. The editor is the
[swift-markdown-engine](https://github.com/emdzej/swift-markdown-engine) fork, a TextKit 2 engine that
blends source and rendering, checked out next to this repository.

## Layout

| Path | What's there |
| --- | --- |
| `apple/project.yml` | XcodeGen project: the `nmw` app (macOS + iOS), `NmwWidgets`, `NmwShare` |
| `apple/App` | App entry point, Info.plist, entitlements, assets, App Intents |
| `apple/Packages/NmwCore` | Notebook model, file I/O, frontmatter, metadata, the index |
| `apple/Packages/NmwUI` | SwiftUI views, editor integration, themes, export and print |
| `apple/Packages/NmwShared` | Code shared with the widgets and the share extension (App Group) |
| `apple/Widgets`, `apple/ShareExtension` | The two extensions |
| `docs/` | The VitePress site (user guide, roadmap) |
| `design/` | Icon proposals and the demo notebook used for screenshots |
| `legacy/` | The archived web prototype |

## Building

Requirements: Xcode 26 (macOS 26 / iOS 26 SDKs), [XcodeGen](https://github.com/yonaskolb/XcodeGen),
and the engine at `../swift-markdown-engine`:

```sh
git clone git@github.com:emdzej/swift-markdown-engine.git ../swift-markdown-engine
cd apple
xcodegen generate
xcodebuild build -project nmw.xcodeproj -scheme nmw -destination 'platform=macOS'
```

Open `apple/nmw.xcodeproj` in Xcode to run it on a simulator or a device. The project is generated,
so edit `project.yml`, not the `.xcodeproj`.

## Tests

```sh
cd apple/Packages/NmwCore && swift test
cd apple/Packages/NmwShared && swift test
cd apple/Packages/NmwUI && xcodebuild test -scheme NmwUI -destination 'platform=macOS'
```

CI (`.github/workflows/ci.yml`) runs all three and builds the app for macOS and iOS. `site.yml`
deploys `docs/` to GitHub Pages.

## Site

```sh
cd docs
npm ci
npm run dev     # or: npm run build
```
