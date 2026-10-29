export type FileEntry = {
  /** Full path from vault root, e.g. "/projects/foo.md". Always uses forward slashes. */
  path: string
  /** Basename without parent path, e.g. "foo.md". */
  name: string
  kind: 'file' | 'directory'
}

/**
 * Storage-agnostic interface for the vault. All paths are absolute from the
 * vault root using forward slashes. Root is "/" (or equivalently "").
 *
 * Implementations: OPFS (browser sandbox), FSA (user-picked folder via
 * File System Access API), native (Tauri, later).
 */
export interface FileSystem {
  /** Read a file as UTF-8 text. Throws if the file does not exist. */
  read(path: string): Promise<string>

  /** Write a file as UTF-8 text. Creates parent directories as needed. */
  write(path: string, content: string): Promise<void>

  /** Delete a file or directory (recursively). No-op if it doesn't exist. */
  delete(path: string): Promise<void>

  /** List immediate children of a directory. Throws if path is not a directory. */
  list(path: string): Promise<FileEntry[]>

  /** Check whether anything exists at the given path. */
  exists(path: string): Promise<boolean>

  /** Move/rename. Implemented as copy+delete for cross-browser safety. */
  move(from: string, to: string): Promise<void>

  /** Create a directory and any missing parents. No-op if it already exists. */
  mkdir(path: string): Promise<void>
}
