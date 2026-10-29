import type { FileSystem } from './types.js'
import { createOpfsFileSystem } from './opfs.js'
import { isFsaSupported } from './fsa.js'

export type FileSystemMode = 'opfs' | 'fsa' | 'native'

export type DetectedFileSystem = {
  fs: FileSystem
  mode: FileSystemMode
  /** True if the user could opt into a real folder via {@link pickDirectory}. */
  canUpgradeToFsa: boolean
}

/**
 * Returns the best available filesystem for first launch. OPFS is the default
 * because it requires no user prompt; the UI can offer an "Open folder…"
 * upgrade path on browsers where {@link canUpgradeToFsa} is true.
 */
export async function detectFileSystem(): Promise<DetectedFileSystem> {
  const fs = await createOpfsFileSystem()
  return {
    fs,
    mode: 'opfs',
    canUpgradeToFsa: isFsaSupported(),
  }
}
