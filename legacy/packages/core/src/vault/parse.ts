export type ParsedNote = {
  frontmatter: Frontmatter
  body: string
  /** Offset of the body inside the original text — useful for editor ranges. */
  bodyStart: number
}

export type Frontmatter = {
  title?: string
  aliases?: string[]
  tags?: string[]
  /** Anything we didn't recognize lives here as raw strings. */
  raw: Record<string, string | string[]>
}

export type WikiLinkRef = {
  /** Raw target text, e.g. "Foo Bar" or "folder/Foo#section". */
  target: string
  /** Display alias if `[[target|display]]`. */
  display: string | undefined
  /** Range in the source text. */
  from: number
  to: number
}

const FRONTMATTER_FENCE = /^---\r?\n/
const TAG_RE = /(?:^|\s)#([A-Za-z][A-Za-z0-9_/-]*)/g
const WIKILINK_RE = /\[\[([^\[\]\n|]+?)(?:\|([^\[\]\n]+?))?\]\]/g
const HEADING1_RE = /^#\s+(.+?)\s*$/m

/**
 * Split frontmatter off the top of a markdown file. Frontmatter is a YAML-ish
 * block delimited by `---`. We only parse a handful of keys — title, aliases,
 * tags — because that's all we use today. Unknown keys are preserved as raw
 * strings so downstream code can still see them.
 */
export function parseFrontmatter(text: string): ParsedNote {
  if (!FRONTMATTER_FENCE.test(text)) {
    return { frontmatter: { raw: {} }, body: text, bodyStart: 0 }
  }
  const firstNewline = text.indexOf('\n') + 1
  const endIdx = text.indexOf('\n---', firstNewline)
  if (endIdx === -1) {
    return { frontmatter: { raw: {} }, body: text, bodyStart: 0 }
  }
  const yamlText = text.slice(firstNewline, endIdx)
  const afterFence = text.indexOf('\n', endIdx + 4)
  const bodyStart = afterFence === -1 ? text.length : afterFence + 1

  const fm = parseSimpleYaml(yamlText)
  return {
    frontmatter: fm,
    body: text.slice(bodyStart),
    bodyStart,
  }
}

/** Pick the best title for a note: frontmatter > first H1 > basename. */
export function deriveTitle(
  frontmatter: Frontmatter,
  body: string,
  basename: string,
): string {
  if (frontmatter.title && frontmatter.title.trim()) return frontmatter.title.trim()
  const h1 = HEADING1_RE.exec(body)
  if (h1?.[1]) return h1[1].trim()
  return basename.replace(/\.md$/i, '')
}

/** Extract inline `#tag` mentions from the body. */
export function extractTags(body: string): string[] {
  const seen = new Set<string>()
  let m: RegExpExecArray | null
  TAG_RE.lastIndex = 0
  while ((m = TAG_RE.exec(body)) !== null) {
    if (m[1]) seen.add(m[1])
  }
  return [...seen]
}

/** Extract every `[[wikilink]]` occurrence with its source range. */
export function extractWikilinks(text: string): WikiLinkRef[] {
  const out: WikiLinkRef[] = []
  let m: RegExpExecArray | null
  WIKILINK_RE.lastIndex = 0
  while ((m = WIKILINK_RE.exec(text)) !== null) {
    const target = m[1]?.trim()
    if (!target) continue
    out.push({
      target,
      display: m[2]?.trim(),
      from: m.index,
      to: m.index + m[0].length,
    })
  }
  return out
}

/**
 * Tiny YAML reader: handles `key: value`, `key: [a, b]`, and the `- item`
 * list form. Anything fancier (nested maps, multi-line scalars) is preserved
 * as a raw string. Will swap for a real YAML parser in M5+.
 */
function parseSimpleYaml(yaml: string): Frontmatter {
  const fm: Frontmatter = { raw: {} }
  const lines = yaml.split(/\r?\n/)
  let currentKey: string | null = null
  let currentList: string[] | null = null

  const commit = () => {
    if (currentKey && currentList) {
      assignFrontmatter(fm, currentKey, currentList)
      currentKey = null
      currentList = null
    }
  }

  for (const raw of lines) {
    if (!raw.trim()) {
      commit()
      continue
    }
    const listItem = raw.match(/^\s+-\s+(.+?)\s*$/)
    if (listItem && currentList && listItem[1]) {
      currentList.push(stripQuotes(listItem[1]))
      continue
    }
    commit()
    const kv = raw.match(/^([A-Za-z_][\w-]*):\s*(.*)$/)
    if (!kv) continue
    const key = kv[1]!
    const value = kv[2] ?? ''
    if (value === '') {
      currentKey = key
      currentList = []
      continue
    }
    const inline = value.match(/^\[(.*)\]$/)
    if (inline?.[1] !== undefined) {
      const items = splitCsv(inline[1]).map(stripQuotes)
      assignFrontmatter(fm, key, items)
    } else {
      assignFrontmatter(fm, key, stripQuotes(value))
    }
  }
  commit()
  return fm
}

function assignFrontmatter(fm: Frontmatter, key: string, value: string | string[]): void {
  fm.raw[key] = value
  if (key === 'title' && typeof value === 'string') fm.title = value
  else if (key === 'aliases' && Array.isArray(value)) fm.aliases = value
  else if (key === 'tags' && Array.isArray(value)) fm.tags = value
}

function splitCsv(s: string): string[] {
  return s
    .split(',')
    .map((p) => p.trim())
    .filter((p) => p.length > 0)
}

function stripQuotes(s: string): string {
  return s.replace(/^["'](.*)["']$/, '$1').trim()
}
