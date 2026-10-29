<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import { EditorView } from '@codemirror/view'
  import { EditorState } from '@codemirror/state'
  import { basicSetup } from 'codemirror'
  import { markdown, markdownLanguage } from '@codemirror/lang-markdown'
  import { languages } from '@codemirror/language-data'
  import { editorTheme } from './editor-theme.js'
  import { wikilinkExtension } from './wikilink-extension.js'
  import { wikilinkCompletion } from './wikilink-completion.js'
  import type { IndexedNote } from '@nmy/core'

  type Props = {
    initialDoc?: string
    onChange?: (doc: string) => void
    onOpenLink?: (target: string) => void
    resolveLink?: (target: string) => boolean
    searchNotes?: (query: string) => IndexedNote[]
  }

  let {
    initialDoc = '',
    onChange,
    onOpenLink,
    resolveLink = () => false,
    searchNotes = () => [],
  }: Props = $props()

  let host: HTMLDivElement
  let view: EditorView | null = null

  onMount(() => {
    view = new EditorView({
      parent: host,
      state: EditorState.create({
        doc: initialDoc,
        extensions: [
          basicSetup,
          markdown({ base: markdownLanguage, codeLanguages: languages, addKeymap: true }),
          EditorView.lineWrapping,
          editorTheme(),
          wikilinkExtension({
            resolve: (target) => resolveLink(target),
            onOpen: (target) => onOpenLink?.(target),
          }),
          wikilinkCompletion({ search: (q) => searchNotes(q) }),
          EditorView.updateListener.of((u) => {
            if (u.docChanged) onChange?.(u.state.doc.toString())
          }),
        ],
      }),
    })
    view.focus()
  })

  onDestroy(() => {
    view?.destroy()
    view = null
  })
</script>

<div bind:this={host} class="editor-host"></div>

<style>
  .editor-host {
    height: 100%;
    overflow: hidden;
    display: flex;
    flex-direction: column;
  }
  .editor-host :global(.cm-editor) {
    flex: 1;
    outline: none;
  }
  .editor-host :global(.cm-editor.cm-focused) {
    outline: none;
  }
</style>
