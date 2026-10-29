import type { FileSystem, FileEntry } from '../filesystem/types.js'

/**
 * Walk the vault yielding every entry under {@link root}. Depth-first; folders
 * are yielded before their children. Hidden entries (starting with ".") and
 * the ".nmy/" metadata directory are skipped.
 */
export async function* walkVault(
  fs: FileSystem,
  root: string = '/',
): AsyncGenerator<FileEntry> {
  const stack: string[] = [root]
  while (stack.length > 0) {
    const current = stack.pop()!
    let entries: FileEntry[]
    try {
      entries = await fs.list(current)
    } catch {
      continue
    }
    for (const entry of entries) {
      if (entry.name.startsWith('.')) continue
      yield entry
      if (entry.kind === 'directory') stack.push(entry.path)
    }
  }
}

/** Filter to markdown files only. */
export async function* walkNotes(
  fs: FileSystem,
  root: string = '/',
): AsyncGenerator<FileEntry> {
  for await (const entry of walkVault(fs, root)) {
    if (entry.kind === 'file' && entry.name.toLowerCase().endsWith('.md')) {
      yield entry
    }
  }
}
