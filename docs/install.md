# Installation

Notes my Way runs on **macOS 26** and **iOS / iPadOS 26** or later.

::: info App Store
An App Store release is <span class="nmw-coming">coming</span>. Until then, build it from source as described below.
:::

## Build from source

You need Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

The editor is a fork of [swift-markdown-engine](https://github.com/emdzej/swift-markdown-engine) and is referenced as a sibling folder, so clone both next to each other:

```bash
git clone https://github.com/emdzej/swift-markdown-engine.git
git clone https://github.com/emdzej/notesmyway.git
cd notesmyway/apple
xcodegen generate
```

### Mac

```bash
xcodebuild build -project nmw.xcodeproj -scheme nmw \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /tmp/nmw-build
cp -R "/tmp/nmw-build/Build/Products/Release/Notes my Way.app" /Applications/
```

The local build is ad-hoc signed and sandboxed. Opening it the first time from Finder may need a right-click › Open.

### iPhone and iPad

Installing on a device needs an Apple Developer account (a free one works, with 7-day provisioning). Pair the device with Xcode once, then:

```bash
xcodebuild build -project nmw.xcodeproj -scheme nmw \
  -configuration Release -destination 'id=<device UDID>' \
  -allowProvisioningUpdates \
  CODE_SIGN_STYLE=Automatic DEVELOPMENT_TEAM=<your team ID> \
  CODE_SIGN_IDENTITY="Apple Development" \
  -derivedDataPath /tmp/nmw-device
xcrun devicectl device install app --device <device UDID> \
  "/tmp/nmw-device/Build/Products/Release-iphoneos/Notes my Way.app"
```

`xcrun devicectl list devices` shows the UDID. The device needs **Developer Mode** on (Settings › Privacy & Security).

Or open `nmw.xcodeproj` in Xcode, pick your team under Signing & Capabilities, choose the device and press Run.

## Make it the default for Markdown files

On the Mac, Settings › General › **Markdown Files** shows which app opens `.md` files and has a button to make Notes my Way the default; macOS asks you to confirm. Finder's Get Info › Open with › Change All… does the same.

On iPhone and iPad there are no default apps for file types; Notes my Way appears in the Files app's share sheet and edits files where they are.
