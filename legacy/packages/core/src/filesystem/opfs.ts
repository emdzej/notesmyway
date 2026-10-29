import { HandleFileSystem } from './handle-fs.js'
import type { FileSystem } from './types.js'

/** Vault backed by the browser's Origin Private File System. */
export async function createOpfsFileSystem(): Promise<FileSystem> {
  if (!('storage' in navigator) || !navigator.storage.getDirectory) {
    throw new Error('OPFS is not supported in this browser')
  }
  const root = await navigator.storage.getDirectory()
  return new HandleFileSystem(root)
}
