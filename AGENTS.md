# AGENTS.md

Notes for coding agents working in this repository. Humans: see [README.md](README.md).

The app is **Notes my Way**, abbreviated **nmw** (not "nmy", the folder name). Bundle ID
`pl.emdzej.notesmyway`. [`spec.md`](spec.md) is the design; keep [`status.md`](status.md) up to date
when a feature lands.

## Ground rules

- **Never touch the developer's own data.** Don't delete or edit `~/Library/Containers/pl.emdzej.notesmyway`
  (their sandbox, library and settings), and don't open their notes for screenshots or tests. Use
  `design/demo-notebook`.
- **Keep `apple/build/Notes my Way.app`.** It's the developer's current Mac build; replace it with a
  fresh Release build after changes, then `touch` it and run
  `lsregister -f` (`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister`)
  so Finder and the Dock pick up the new icon and document types.
- **Clean up** what you create: derived data in `/tmp`, simulator installs, screenshot copies.
- **The site is for users.** `docs/` may link to this repository (source, licence, releases, issues), but
  build-from-source instructions belong in the README, not on the site.
- **Keep personal data out of git:** the developer's personal email only in commits, no device names or IDs
  (they go in `AGENTS.local.md`). Tags are the bare version, without a "v".

## The editor engine

The editor is [MarkdownKit](https://github.com/emdzej/markdownkit) in `../markdownkit` (public, our own
engine, derived from `nodes-app/swift-markdown-engine`; committing on its `main` is fine). Its `upstream`
remote is the original: port fixes from it selectively, never merge it wholesale (the code bases diverged).
NmwUI depends on it by relative path. When the app needs new engine commits, push the engine first:
CI clones it next to this repository.

## Building and testing

- **Project:** XcodeGen. Edit `apple/project.yml`, run `xcodegen generate` in `apple/`. The `.xcodeproj`
  is not committed.
- **NmwCore, NmwShared:** `swift test` in the package folder.
- **NmwUI:** `xcodebuild test -scheme NmwUI -destination 'platform=macOS'` from
  `apple/Packages/NmwUI` (`swift test` can't link the engine's dynamic product). Use a fresh
  `-derivedDataPath` in `/tmp` if a build behaves oddly.
- **Engine:** `swift test` in the engine. Two `ScrollingHeaderController` animation tests fail while the
  screen is locked; that's expected.
- **Mac app:** `xcodebuild build -project nmw.xcodeproj -scheme nmw -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/nmw-mac-dd`.
  macOS signs ad hoc with `App/nmw-macOS.entitlements`. That file is static (not generated): sandbox,
  user-selected files, bookmarks, network client, printing (`com.apple.security.print`; without it
  ⌘P says "This application does not support printing") and the team-prefixed App Group.

## Signing and devices

- **App Group:** the app, `NmwWidgets` and `NmwShare` share `group.pl.emdzej.notesmyway`. On macOS it's
  team-prefixed (`<TEAM ID>.group.pl.emdzej.notesmyway`) in `App/nmw-macOS.entitlements`, the extensions'
  macOS entitlements and `NmwShared/AppGroup.swift`. To build under your own team, change the team ID there
  and the bundle IDs in `project.yml`. `NMW_APP_GROUPS=NO` builds without the group (for signing without an
  Apple ID); the widgets and the share extension then can't see the app's data.
- **Device builds:** pass `CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=<team> CODE_SIGN_IDENTITY="Apple Development" -allowProvisioningUpdates`.
  If a build fails with "Profile doesn't match the entitlements… application-groups", delete the stale
  profile in `~/Library/Developer/Xcode/UserData/Provisioning Profiles` and build again; if it persists,
  the App ID lacks the group on the developer portal. `IXRemoteErrorDomain` 6 on install: retry.
- **This Mac's own device and deploy routine**, if any, is in `AGENTS.local.md` (git-ignored). Read it when
  it exists.

## Releases

- **Version:** `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` in `apple/project.yml` (one setting for the app
  and both extensions). Tags are the bare version, without a "v": `0.1.0`.
- **Mac DMG:** `NMW_TEAM=<team> NMW_NOTARY_PROFILE=<notarytool profile> apple/scripts/release-mac.sh` builds
  with a Developer ID, makes the DMG, signs, notarises and staples it, and checks it with `spctl`. The DMG is
  attached to the GitHub release by hand for now.

## Pushing

Push over SSH: `git push git@github.com:emdzej/notesmyway.git main`, then `git fetch origin`. The HTTPS
`gh` token lacks the `workflow` scope, so pushes touching `.github/workflows` fail over HTTPS. CI runs on
`macos-26`; `site.yml` deploys `docs/` to <https://notesmyway.emdzej.pl>.

## Screenshots

DEBUG builds take launch arguments (see `Library.swift` and `NotebookView.swift`):

| Argument | Effect |
| --- | --- |
| `-NmwOpenNotebook <path>` | Opens a folder as a notebook; a relative path is under the app's Documents |
| `-NmwScope all\|pinned\|folder:<path>\|tag:<tag>` | Selects the scope once indexing is done |
| `-NmwOpenNote <path>` | Opens a note (notebook-relative) |
| `-NmwCompactColumn content\|detail` | iPhone: start on the note list or the note |
| `-NmwColumnVisibility all\|doubleColumn` | iPad and Mac: which columns show |
| `-NmwSettingsPage general\|appearance\|themes` | iPhone and iPad: opens that Settings page |
| `-nmw.theme paper`, `-nmw.editorMode source`, `-nmw.appearance dark` | Any setting, as a UserDefaults argument |

- **iPhone and iPad:** simulators (iPhone 17 Pro, iPad Pro 13-inch). Copy `design/demo-notebook` into the
  app container's `Documents/Demo`, launch with `-NmwOpenNotebook Demo`, set the status bar to 09:41
  with `simctl status_bar … override`, and capture with `simctl io … screenshot`.
- **Mac:** build a Debug copy with `PRODUCT_BUNDLE_IDENTIFIER=pl.emdzej.notesmyway.shots`, so it gets its
  own sandbox container. Remove its `PlugIns` and re-sign it ad hoc with `App/nmw-macOS.entitlements`.
  Copy the demo notebook into that container's `Documents/Demo`, and set
  `"NSWindow Frame main-AppWindow-1"` in its preferences for the window size. Then capture only its window
  with `screencapture -l <window id>` (from `CGWindowListCopyWindowInfo`), never the whole screen.
  Delete the container afterwards. The sidebar's glass doesn't render offscreen, so prefer real window
  captures over `SiteScreenshotTests`.
- **Site sizes:** Mac 1600 px wide (keep the alpha and window shadow), iPad 1200 × 1600, iPhone 600 px
  wide, all WebP in `docs/public/screenshots/`.

## Licences

Every dependency's licence ships in the app: `Settings › About` (`Views/AboutView.swift`) reads the texts in
`NmwUI/Sources/NmwUI/Resources/Acknowledgements/`. Adding a dependency means adding its licence file, an
`Acknowledgement.all` entry and a row in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).

## Conventions

- Swift 6, SwiftUI with `@Observable`; platform code behind `#if os(macOS)` / `#if os(iOS)`.
- Settings are `@AppStorage` keys prefixed `nmw.`; per-notebook settings live in the notebook's
  `.nmw/config.json`.
- Themes (`Editor/EditorTheme.swift`): built-ins plus JSON / `.nmwtheme` files in the Themes folder.
  The theme drives the accent and page colors app-wide (`EditorAppearance`, `Palette.accentColor`).
- Comments explain why, not what; match the surrounding density.
