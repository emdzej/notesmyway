import {
  Decoration,
  EditorView,
  MatchDecorator,
  ViewPlugin,
  type DecorationSet,
  type ViewUpdate,
} from '@codemirror/view'
import type { Extension } from '@codemirror/state'

const WIKILINK_RE = /\[\[([^\[\]\n|]+?)(?:\|([^\[\]\n]+?))?\]\]/g

export type WikilinkExtensionOptions = {
  /** Returns true if the link target resolves to an existing note. */
  resolve: (target: string) => boolean
  /** Called on Cmd/Ctrl-click of a wikilink. */
  onOpen: (target: string) => void
}

/**
 * Decorates `[[wikilink]]` occurrences with a `.cm-wikilink` class (and
 * `.cm-wikilink-broken` when {@link resolve} returns false). A Cmd/Ctrl-click
 * on the rendered span calls {@link onOpen} with the raw target text.
 */
export function wikilinkExtension(options: WikilinkExtensionOptions): Extension {
  const matcher = new MatchDecorator({
    regexp: WIKILINK_RE,
    decoration: (match) => {
      const target = match[1]?.trim() ?? ''
      const broken = !options.resolve(target)
      return Decoration.mark({
        class: broken ? 'cm-wikilink cm-wikilink-broken' : 'cm-wikilink',
        attributes: { 'data-wikilink': target },
      })
    },
  })

  const plugin = ViewPlugin.fromClass(
    class {
      decorations: DecorationSet
      constructor(view: EditorView) {
        this.decorations = matcher.createDeco(view)
      }
      update(u: ViewUpdate) {
        this.decorations = matcher.updateDeco(u, this.decorations)
      }
    },
    { decorations: (v) => v.decorations },
  )

  const clickHandler = EditorView.domEventHandlers({
    mousedown(event) {
      if (!(event.metaKey || event.ctrlKey)) return false
      const targetEl = event.target as HTMLElement | null
      const span = targetEl?.closest('[data-wikilink]') as HTMLElement | null
      if (!span) return false
      const target = span.getAttribute('data-wikilink')
      if (!target) return false
      event.preventDefault()
      options.onOpen(target)
      return true
    },
  })

  return [plugin, clickHandler]
}
