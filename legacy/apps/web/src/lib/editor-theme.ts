import { EditorView } from '@codemirror/view'
import { HighlightStyle, syntaxHighlighting } from '@codemirror/language'
import { tags as t } from '@lezer/highlight'
import type { Extension } from '@codemirror/state'

/**
 * Editor chrome theme — uses CSS variables so it follows the app's
 * light/dark scheme automatically.
 */
const chrome = EditorView.theme({
  '&': {
    color: 'var(--fg)',
    backgroundColor: 'transparent',
    height: '100%',
    fontSize: '15px',
  },
  '.cm-scroller': {
    fontFamily:
      'ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, sans-serif',
    lineHeight: '1.65',
    padding: '24px max(24px, env(safe-area-inset-right)) 40vh max(24px, env(safe-area-inset-left))',
  },
  '.cm-content': {
    caretColor: 'var(--accent)',
    maxWidth: '760px',
    margin: '0 auto',
  },
  '.cm-line': {
    padding: '0',
  },
  '.cm-cursor, .cm-dropCursor': {
    borderLeftColor: 'var(--accent)',
    borderLeftWidth: '2px',
  },
  '&.cm-focused > .cm-scroller > .cm-selectionLayer .cm-selectionBackground, .cm-selectionBackground, .cm-content ::selection':
    {
      backgroundColor: 'var(--selection)',
    },
  '.cm-activeLine': {
    backgroundColor: 'transparent',
  },
  '.cm-gutters': {
    display: 'none',
  },
  '.cm-foldPlaceholder': {
    backgroundColor: 'var(--code-bg)',
    color: 'var(--fg-muted)',
    border: '1px solid var(--border)',
  },
  '.cm-wikilink': {
    color: 'var(--accent)',
    textDecoration: 'underline',
    textUnderlineOffset: '3px',
    textDecorationThickness: '1px',
  },
  '.cm-wikilink-broken': {
    color: 'var(--error)',
    textDecorationStyle: 'dashed',
  },
})

/**
 * Markdown syntax styling — gives headings size + weight, dims punctuation,
 * styles links, code, quotes. Source markers ("#", "*") stay visible by
 * design — full live-preview hiding lands as a separate extension.
 */
const mdHighlight = HighlightStyle.define([
  { tag: t.heading1, fontSize: '1.9em', fontWeight: '700', lineHeight: '1.25' },
  { tag: t.heading2, fontSize: '1.55em', fontWeight: '700', lineHeight: '1.3' },
  { tag: t.heading3, fontSize: '1.3em', fontWeight: '600' },
  { tag: t.heading4, fontSize: '1.15em', fontWeight: '600' },
  { tag: t.heading5, fontWeight: '600' },
  { tag: t.heading6, fontWeight: '600', color: 'var(--fg-muted)' },

  { tag: t.strong, fontWeight: '700' },
  { tag: t.emphasis, fontStyle: 'italic' },
  { tag: t.strikethrough, textDecoration: 'line-through' },

  { tag: t.link, color: 'var(--accent)' },
  { tag: t.url, color: 'var(--accent)' },

  {
    tag: [t.monospace, t.literal],
    fontFamily: 'ui-monospace, SFMono-Regular, Menlo, monospace',
    fontSize: '0.92em',
    backgroundColor: 'var(--code-bg)',
    padding: '1px 4px',
    borderRadius: '4px',
  },

  { tag: t.quote, color: 'var(--fg-muted)', fontStyle: 'italic' },
  { tag: t.list, color: 'var(--fg)' },
  { tag: t.contentSeparator, color: 'var(--border)' },

  // Dim the markdown punctuation so headings/bold/italic feel WYSIWYG-ish.
  { tag: t.processingInstruction, color: 'var(--fg-muted)' },
  { tag: t.punctuation, color: 'var(--fg-muted)' },
])

export function editorTheme(): Extension {
  return [chrome, syntaxHighlighting(mdHighlight, { fallback: true })]
}
