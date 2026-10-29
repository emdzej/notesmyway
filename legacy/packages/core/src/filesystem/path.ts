/** Split a path into non-empty segments. "/" → []; "/a/b/" → ["a", "b"]. */
export function segments(path: string): string[] {
  return path.split('/').filter((s) => s.length > 0)
}

/** Last segment of a path. "/a/b.md" → "b.md"; "/" → "". */
export function basename(path: string): string {
  const segs = segments(path)
  return segs[segs.length - 1] ?? ''
}

/** Parent directory of a path. "/a/b.md" → "/a"; "/a" → "/". */
export function dirname(path: string): string {
  const segs = segments(path)
  if (segs.length <= 1) return '/'
  return '/' + segs.slice(0, -1).join('/')
}

/** Join segments into a leading-slash path. */
export function joinPath(...parts: string[]): string {
  const all = parts.flatMap(segments)
  return all.length === 0 ? '/' : '/' + all.join('/')
}
