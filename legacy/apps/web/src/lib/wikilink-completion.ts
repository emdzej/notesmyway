import type {
  Completion,
  CompletionContext,
  CompletionResult,
  CompletionSource,
} from '@codemirror/autocomplete'
import { markdownLanguage } from '@codemirror/lang-markdown'
import type { Extension } from '@codemirror/state'
import type { IndexedNote } from '@nmy/core'

export type WikilinkCompletionOptions = {
  search: (query: string) => IndexedNote[]
}

/**
 * CodeMirror completion source that triggers inside `[[…` and offers note
 * titles from the vault. Attached to the markdown language so it's only
 * active in prose, not inside fenced code blocks.
 */
export function wikilinkCompletion(options: WikilinkCompletionOptions): Extension {
  const source: CompletionSource = (ctx: CompletionContext): CompletionResult | null => {
    const before = ctx.matchBefore(/\[\[[^\]\n|]*/)
    if (!before) return null
    if (before.from === before.to && !ctx.explicit) return null

    const query = before.text.slice(2)
    const matches = options.search(query)
    if (matches.length === 0 && !ctx.explicit) return null

    return {
      from: before.from + 2,
      to: ctx.pos,
      validFor: /^[^\]\n|]*$/,
      options: matches.map<Completion>((note) => ({
        label: note.title,
        apply: `${note.title}]]`,
        detail: humanPath(note.path),
        type: 'wikilink',
      })),
    }
  }

  return markdownLanguage.data.of({ autocomplete: source })
}

function humanPath(path: string): string {
  return path.replace(/^\//, '').replace(/\.md$/i, '')
}
