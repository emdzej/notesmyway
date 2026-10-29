# What is Notes my Way?

I like Apple Notes. It's fast, it's always there, and it never asks me to think about where a note goes. What I don't like is that my notes live inside it. I can't grep them, I can't put them in git, and the day I want to leave, I get an export, not my notes.

Obsidian solves that — the notes are plain files. But I wanted a native app: fast, and built for the system it runs on, not a web page in a window. So I built it: Apple Notes on the outside, a folder of Markdown files on the inside.

## Files are the truth

A notebook is just a folder. Every note is a `.md` file, folders are real folders, and attachments are ordinary files next to the notes. Anything the app does, you can also do with any other tool. There's a small SQLite index for search, tags and backlinks, but it only holds what can be rebuilt from the files. Delete it and nothing is lost.

Is that new? Not really. It's the same promise Obsidian makes, and you can point Notes my Way at an Obsidian vault and it opens as a notebook.

## Blend, don't hide

The editor renders Markdown in place: headings look like headings, `**bold**` looks bold, and the markers fold away when the caret is somewhere else. Move onto the line and they're back, exactly as you typed them. The bytes on disk are never rewritten behind your back.

When you'd rather see everything, ⇧⌘M switches the note to source mode — monospaced, with syntax colours — and back.

## What's there and what isn't

Today the app opens folders as notebooks, with nested folders, tags, pinned notes, full-text search, backlinks, an outline, attachment handling, link preview cards, editable tables with formulas, and themes. It runs on macOS 26 and iOS / iPadOS 26, and it's [coming soon to the App Store](/get-the-app).

What's missing? Sync, for one. Notes my Way works with any folder, so Dropbox, Syncthing or a git repo already do the job, but built-in iCloud sync and a small self-hosted sync server are on the [roadmap](/backlog).

## Why bother?

Because notes outlive apps. Every move between note apps costs something — formatting, attachments, links. My point is — if the notes are plain files, the next move costs nothing.
