# Contributing to Notes my Way

Thank you for wanting to help. Bug reports, ideas and pull requests are welcome.

## Before you start

- **Bugs:** open an issue with what you did, what you expected and what happened, plus the macOS or iOS
  version. A small notebook folder that shows the problem helps most.
- **Features:** open an issue first, so we can agree on the shape before you write the code. The design is
  in [`spec.md`](spec.md); [`docs/backlog.md`](docs/backlog.md) is the roadmap.
- **The editor** lives in a separate repository, [MarkdownKit](https://github.com/emdzej/markdownkit)
  (Apache 2.0). Editing behaviour, tables and rendering usually belong there.

## Building

See [README.md](README.md#building). In short: Xcode 26, XcodeGen, and MarkdownKit checked out at
`../markdownkit`. Run the tests before opening a pull request:

```sh
cd apple/Packages/NmwCore && swift test
cd apple/Packages/NmwShared && swift test
cd apple/Packages/NmwUI && xcodebuild test -scheme NmwUI -destination 'platform=macOS'
```

## Pull requests

- Keep each one to one change, with tests for anything that can be tested.
- Match the code around you: Swift 6, SwiftUI with `@Observable`, comments that say why rather than what.
- Notes are the user's files. Never rewrite a file the user didn't change, and never add a format that
  only Notes my Way can read.
- New dependencies need a licence compatible with GPLv3, an entry in Settings › About and a row in
  [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md).

## Licence of contributions

Notes my Way is licensed under the [GNU General Public License v3](LICENSE). It's also distributed through
the App Store, whose terms the GPL doesn't allow for code its author hasn't agreed to. So every
contribution comes with the [Contributor Licence Agreement](CLA.md): you keep the copyright to your work and
license it under the GPLv3 like the rest of the project, and you also give the maintainer the right to
distribute it under other terms, such as the App Store's.

Agree to it by adding this line to your first pull request's description:

> I have read the Contributor Licence Agreement in CLA.md and agree to it for this and my future
> contributions to Notes my Way.

and sign off your commits (`git commit -s`), which certifies you have the right to submit them
([Developer Certificate of Origin](https://developercertificate.org)).
