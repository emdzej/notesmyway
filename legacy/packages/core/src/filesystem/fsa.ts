import { HandleFileSystem } from './handle-fs.js'
import type { FileSystem } from './types.js'

/**
 * Vault backed by a user-picked folder via the File System Access API.
 * Available on Chromium desktop. Not on iOS Safari or Firefox — callers
 * should feature-detect first.
 */
export async function createFsaFileSystem(
  handle: FileSystemDirectoryHandle,
): Promise<FileSystem> {
  const permission = await ensureWritable(handle)
  if (permission !== 'granted') {
    throw new Error(`folder access not granted (state: ${permission})`)
  }
  return new HandleFileSystem(handle)
}

/** Open the native directory picker. Returns null if the user cancels. */
export async function pickDirectory(): Promise<FileSystemDirectoryHandle | null> {
  if (!isFsaSupported()) {
    throw new Error('File System Access API is not supported in this browser')
  }
  try {
    return await window.showDirectoryPicker({ mode: 'readwrite' })
  } catch (e) {
    if (e instanceof DOMException && e.name === 'AbortError') return null
    throw e
  }
}

export function isFsaSupported(): boolean {
  return typeof window !== 'undefined' && 'showDirectoryPicker' in window
}

async function ensureWritable(
  handle: FileSystemDirectoryHandle,
): Promise<PermissionState> {
  const opts: FileSystemHandlePermissionDescriptor = { mode: 'readwrite' }
  const current = await handle.queryPermission(opts)
  if (current === 'granted') return current
  return await handle.requestPermission(opts)
}

declare global {
  interface Window {
    showDirectoryPicker(options?: {
      mode?: 'read' | 'readwrite'
      startIn?: FileSystemHandle | string
    }): Promise<FileSystemDirectoryHandle>
  }

  interface FileSystemHandle {
    queryPermission(descriptor: FileSystemHandlePermissionDescriptor): Promise<PermissionState>
    requestPermission(descriptor: FileSystemHandlePermissionDescriptor): Promise<PermissionState>
  }

  interface FileSystemHandlePermissionDescriptor {
    mode?: 'read' | 'readwrite'
  }
}
