export type { FileSystem, FileEntry } from './filesystem/types.js'
export { createOpfsFileSystem } from './filesystem/opfs.js'
export { createFsaFileSystem, pickDirectory } from './filesystem/fsa.js'
export {
  detectFileSystem,
  type DetectedFileSystem,
  type FileSystemMode,
} from './filesystem/detect.js'
export { basename, dirname, joinPath, segments } from './filesystem/path.js'

export { walkVault, walkNotes } from './vault/walk.js'
export {
  parseFrontmatter,
  deriveTitle,
  extractTags,
  extractWikilinks,
  type Frontmatter,
  type ParsedNote,
  type WikiLinkRef,
} from './vault/parse.js'
export { VaultIndex, type IndexedNote, type Backlink } from './vault/index.js'
