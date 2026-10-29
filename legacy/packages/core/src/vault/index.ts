import type { FileSystem } from '../filesystem/types.js'
import { basename } from '../filesystem/path.js'
import { walkNotes } from './walk.js'
import { deriveTitle, extractTags, extractWikilinks, parseFrontmatter } from './parse.js'

export type IndexedNote = {
  path: string
  title: string
  aliases: string[]
  tags: string[]
  /** Outgoing wikilink targets (resolved or not, raw text). */
  outgoing: string[]
}

export type Backlink = {
  /** Source note that contains the link. */
  fromPath: string
  fromTitle: string
  /** Display text on the link, when an alias was used. */
  display: string | undefined
}

/**
 * In-memory vault index. Source of truth is still disk — the index is a
 * rebuildable derivative. Lookups are sync; mutations (upsert/remove) are
 * called by the app after each disk write.
 */
export class VaultIndex {
  private notes = new Map<string, IndexedNote>()

  /** target key (lowercased) → set of source paths */
  private backlinks = new Map<string, Set<string>>()

  /** lowercased title → paths that have that title */
  private titleIndex = new Map<string, Set<string>>()

  /** lowercased alias → paths */
  private aliasIndex = new Map<string, Set<string>>()

  /** Rebuild from scratch by walking the vault. */
  async rebuild(fs: FileSystem, root: string = '/'): Promise<void> {
    this.notes.clear()
    this.backlinks.clear()
    this.titleIndex.clear()
    this.aliasIndex.clear()
    for await (const entry of walkNotes(fs, root)) {
      try {
        const content = await fs.read(entry.path)
        this.upsertFromContent(entry.path, content)
      } catch {
        /* unreadable file — skip */
      }
    }
  }

  /** Parse content and update the index for one note. */
  upsertFromContent(path: string, content: string): void {
    const parsed = parseFrontmatter(content)
    const title = deriveTitle(parsed.frontmatter, parsed.body, basename(path))
    const wikilinks = extractWikilinks(parsed.body)
    const tags = mergeTags(parsed.frontmatter.tags ?? [], extractTags(parsed.body))

    const note: IndexedNote = {
      path,
      title,
      aliases: parsed.frontmatter.aliases ?? [],
      tags,
      outgoing: wikilinks.map((w) => w.target),
    }

    this.removeBacklinksFrom(path)
    this.notes.set(path, note)
    this.indexLookups(note)
    for (const w of wikilinks) {
      const key = normalizeTarget(w.target)
      let bucket = this.backlinks.get(key)
      if (!bucket) {
        bucket = new Set()
        this.backlinks.set(key, bucket)
      }
      bucket.add(path)
    }
  }

  /** Drop one note from the index. */
  remove(path: string): void {
    const note = this.notes.get(path)
    if (!note) return
    this.unindexLookups(note)
    this.removeBacklinksFrom(path)
    this.notes.delete(path)
  }

  get(path: string): IndexedNote | undefined {
    return this.notes.get(path)
  }

  all(): IndexedNote[] {
    return [...this.notes.values()]
  }

  /** All notes whose title or alias matches the given target (case-insensitive). */
  resolveLink(target: string): IndexedNote | null {
    const key = normalizeTarget(target).split('#')[0]?.split('|')[0] ?? ''
    if (!key) return null

    if (key.includes('/')) {
      const normalized = key.endsWith('.md') ? key : `${key}.md`
      const path = normalized.startsWith('/') ? normalized : `/${normalized}`
      return this.notes.get(path) ?? null
    }

    const byTitle = this.titleIndex.get(key)
    if (byTitle && byTitle.size > 0) {
      const first = [...byTitle][0]!
      return this.notes.get(first) ?? null
    }
    const byAlias = this.aliasIndex.get(key)
    if (byAlias && byAlias.size > 0) {
      const first = [...byAlias][0]!
      return this.notes.get(first) ?? null
    }
    for (const note of this.notes.values()) {
      const stem = basename(note.path).toLowerCase().replace(/\.md$/, '')
      if (stem === key) return note
    }
    return null
  }

  /** Notes that link to {@link path} via its title, alias, or path. */
  getBacklinks(path: string): Backlink[] {
    const note = this.notes.get(path)
    if (!note) return []

    const keys = new Set<string>()
    keys.add(normalizeTarget(note.title))
    for (const alias of note.aliases) keys.add(normalizeTarget(alias))
    const stem = basename(path).toLowerCase().replace(/\.md$/, '')
    keys.add(stem)

    const sources = new Set<string>()
    for (const key of keys) {
      const bucket = this.backlinks.get(key)
      if (bucket) for (const src of bucket) sources.add(src)
    }
    sources.delete(path)

    const result: Backlink[] = []
    for (const src of sources) {
      const srcNote = this.notes.get(src)
      if (!srcNote) continue
      result.push({ fromPath: src, fromTitle: srcNote.title, display: undefined })
    }
    return result.sort((a, b) => a.fromTitle.localeCompare(b.fromTitle))
  }

  /**
   * Search titles + aliases for a fuzzy-ish prefix match. Cheap O(n) scan —
   * fine for vaults under ~10k notes; swap for FTS later.
   */
  searchTitles(query: string, limit: number = 20): IndexedNote[] {
    const q = query.trim().toLowerCase()
    if (!q) return this.all().slice(0, limit)
    const scored: { note: IndexedNote; score: number }[] = []
    for (const note of this.notes.values()) {
      const title = note.title.toLowerCase()
      let score = 0
      if (title === q) score = 100
      else if (title.startsWith(q)) score = 80
      else if (title.includes(q)) score = 60
      else if (note.aliases.some((a) => a.toLowerCase().includes(q))) score = 50
      else if (basename(note.path).toLowerCase().includes(q)) score = 40
      if (score > 0) scored.push({ note, score })
    }
    scored.sort((a, b) => b.score - a.score || a.note.title.localeCompare(b.note.title))
    return scored.slice(0, limit).map((s) => s.note)
  }

  private indexLookups(note: IndexedNote): void {
    addTo(this.titleIndex, normalizeTarget(note.title), note.path)
    for (const alias of note.aliases) addTo(this.aliasIndex, normalizeTarget(alias), note.path)
  }

  private unindexLookups(note: IndexedNote): void {
    removeFrom(this.titleIndex, normalizeTarget(note.title), note.path)
    for (const alias of note.aliases) removeFrom(this.aliasIndex, normalizeTarget(alias), note.path)
  }

  /** Remove all backlinks whose source is {@link path}. Used before upserting. */
  private removeBacklinksFrom(path: string): void {
    const previous = this.notes.get(path)
    if (!previous) return
    for (const target of previous.outgoing) {
      const key = normalizeTarget(target)
      const bucket = this.backlinks.get(key)
      if (!bucket) continue
      bucket.delete(path)
      if (bucket.size === 0) this.backlinks.delete(key)
    }
  }
}

function normalizeTarget(s: string): string {
  return s.trim().toLowerCase()
}

function mergeTags(a: string[], b: string[]): string[] {
  return [...new Set([...a, ...b])]
}

function addTo(map: Map<string, Set<string>>, key: string, value: string): void {
  let bucket = map.get(key)
  if (!bucket) {
    bucket = new Set()
    map.set(key, bucket)
  }
  bucket.add(value)
}

function removeFrom(map: Map<string, Set<string>>, key: string, value: string): void {
  const bucket = map.get(key)
  if (!bucket) return
  bucket.delete(value)
  if (bucket.size === 0) map.delete(key)
}
