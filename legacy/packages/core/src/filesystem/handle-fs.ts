import type { FileSystem, FileEntry } from './types.js'
import { basename, dirname, joinPath, segments } from './path.js'

/**
 * FileSystem implementation backed by a FileSystemDirectoryHandle. Used by
 * both OPFS (root from navigator.storage.getDirectory()) and FSA (root from
 * window.showDirectoryPicker()) — the underlying API is the same.
 */
export class HandleFileSystem implements FileSystem {
  constructor(private readonly root: FileSystemDirectoryHandle) {}

  async read(path: string): Promise<string> {
    const handle = await this.getFile(path, false)
    const file = await handle.getFile()
    return await file.text()
  }

  async write(path: string, content: string): Promise<void> {
    const handle = await this.getFile(path, true)
    const writable = await handle.createWritable()
    await writable.write(content)
    await writable.close()
  }

  async delete(path: string): Promise<void> {
    const segs = segments(path)
    if (segs.length === 0) return
    const parent = await this.getDirectory(dirname(path), false)
    if (!parent) return
    try {
      await parent.removeEntry(basename(path), { recursive: true })
    } catch (e) {
      if (!isNotFound(e)) throw e
    }
  }

  async list(path: string): Promise<FileEntry[]> {
    const dir = await this.getDirectory(path, false)
    if (!dir) throw new Error(`not a directory: ${path}`)
    const out: FileEntry[] = []
    for await (const [name, handle] of dir.entries()) {
      out.push({
        name,
        path: joinPath(path, name),
        kind: handle.kind,
      })
    }
    out.sort((a, b) => {
      if (a.kind !== b.kind) return a.kind === 'directory' ? -1 : 1
      return a.name.localeCompare(b.name)
    })
    return out
  }

  async exists(path: string): Promise<boolean> {
    if (segments(path).length === 0) return true
    const parent = await this.getDirectory(dirname(path), false)
    if (!parent) return false
    const name = basename(path)
    try {
      await parent.getFileHandle(name)
      return true
    } catch (e) {
      if (!isNotFound(e)) throw e
    }
    try {
      await parent.getDirectoryHandle(name)
      return true
    } catch (e) {
      if (!isNotFound(e)) throw e
    }
    return false
  }

  async move(from: string, to: string): Promise<void> {
    const content = await this.read(from)
    await this.write(to, content)
    await this.delete(from)
  }

  async mkdir(path: string): Promise<void> {
    await this.getDirectory(path, true)
  }

  private async getDirectory(
    path: string,
    create: boolean,
  ): Promise<FileSystemDirectoryHandle | null> {
    let dir = this.root
    for (const seg of segments(path)) {
      try {
        dir = await dir.getDirectoryHandle(seg, { create })
      } catch (e) {
        if (!create && isNotFound(e)) return null
        throw e
      }
    }
    return dir
  }

  private async getFile(path: string, create: boolean): Promise<FileSystemFileHandle> {
    const parent = await this.getDirectory(dirname(path), create)
    if (!parent) throw new Error(`directory not found: ${dirname(path)}`)
    return await parent.getFileHandle(basename(path), { create })
  }
}

function isNotFound(e: unknown): boolean {
  return e instanceof DOMException && e.name === 'NotFoundError'
}
