<script module lang="ts">
  export type PaletteItem = {
    id: string
    label: string
    hint?: string
    group?: string
    /** Disable visually; selecting a disabled item is a no-op. */
    disabled?: boolean
  }
</script>

<script lang="ts">
  import { tick } from 'svelte'

  type Props = {
    open: boolean
    placeholder?: string
    items: PaletteItem[]
    onSelect: (item: PaletteItem) => void
    onClose: () => void
  }

  let { open, placeholder = 'Search…', items, onSelect, onClose }: Props = $props()

  let query = $state('')
  let cursor = $state(0)
  let input: HTMLInputElement | undefined = $state()

  const filtered = $derived.by(() => {
    const q = query.trim().toLowerCase()
    if (!q) return items.slice(0, 100)
    const scored: { item: PaletteItem; score: number }[] = []
    for (const item of items) {
      const label = item.label.toLowerCase()
      let score = 0
      if (label === q) score = 100
      else if (label.startsWith(q)) score = 80
      else if (label.includes(q)) score = 60
      else if (item.hint?.toLowerCase().includes(q)) score = 40
      if (score > 0) scored.push({ item, score })
    }
    scored.sort((a, b) => b.score - a.score)
    return scored.slice(0, 100).map((s) => s.item)
  })

  $effect(() => {
    if (open) {
      query = ''
      cursor = 0
      tick().then(() => input?.focus())
    }
  })

  $effect(() => {
    void filtered
    cursor = 0
  })

  function commit(item: PaletteItem) {
    if (item.disabled) return
    onSelect(item)
  }

  function onKey(e: KeyboardEvent) {
    if (!open) return
    if (e.key === 'Escape') {
      e.preventDefault()
      onClose()
      return
    }
    const len = filtered.length
    if (len === 0) return
    if (e.key === 'ArrowDown') {
      e.preventDefault()
      cursor = (cursor + 1) % len
      return
    }
    if (e.key === 'ArrowUp') {
      e.preventDefault()
      cursor = (cursor - 1 + len) % len
      return
    }
    if (e.key === 'Enter') {
      e.preventDefault()
      const it = filtered[cursor]
      if (it) commit(it)
      return
    }
    if ((e.metaKey || e.ctrlKey) && e.key === 'n') {
      e.preventDefault()
      cursor = Math.min(cursor + 1, len - 1)
      return
    }
    if ((e.metaKey || e.ctrlKey) && e.key === 'p') {
      e.preventDefault()
      cursor = Math.max(cursor - 1, 0)
      return
    }
  }
</script>

{#if open}
  <div
    class="overlay"
    role="presentation"
    onmousedown={onClose}
    onkeydown={onKey}
  >
    <div
      class="palette"
      role="dialog"
      aria-modal="true"
      tabindex="-1"
      onmousedown={(e) => e.stopPropagation()}
    >
      <input
        bind:this={input}
        bind:value={query}
        type="text"
        spellcheck="false"
        autocomplete="off"
        autocapitalize="off"
        {placeholder}
        onkeydown={onKey}
      />
      <ul>
        {#each filtered as item, i (item.id)}
          <li
            class:cursor={i === cursor}
            class:disabled={item.disabled}
            onmousedown={(e) => {
              e.preventDefault()
              commit(item)
            }}
            onmouseenter={() => (cursor = i)}
            role="option"
            aria-selected={i === cursor}
          >
            <div class="row">
              {#if item.group}
                <span class="group">{item.group}</span>
              {/if}
              <span class="label">{item.label}</span>
            </div>
            {#if item.hint}
              <span class="hint">{item.hint}</span>
            {/if}
          </li>
        {/each}
        {#if filtered.length === 0}
          <li class="empty">no matches</li>
        {/if}
      </ul>
    </div>
  </div>
{/if}

<style>
  .overlay {
    position: fixed;
    inset: 0;
    background: color-mix(in srgb, var(--bg) 70%, transparent);
    backdrop-filter: blur(4px);
    z-index: 1000;
    display: flex;
    justify-content: center;
    align-items: flex-start;
    padding-top: clamp(40px, 12vh, 120px);
  }

  .palette {
    width: min(560px, 90vw);
    background: var(--sidebar);
    border: 1px solid var(--border);
    border-radius: 10px;
    box-shadow:
      0 16px 48px -16px rgb(0 0 0 / 0.4),
      0 4px 12px -4px rgb(0 0 0 / 0.15);
    overflow: hidden;
    display: flex;
    flex-direction: column;
    max-height: 70vh;
  }

  input {
    border: none;
    background: transparent;
    color: var(--fg);
    font: inherit;
    font-size: 15px;
    padding: 14px 18px;
    outline: none;
    border-bottom: 1px solid var(--border);
  }

  input::placeholder {
    color: var(--fg-muted);
  }

  ul {
    list-style: none;
    margin: 0;
    padding: 6px;
    overflow-y: auto;
    flex: 1;
  }

  li {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 12px;
    padding: 8px 12px;
    border-radius: 6px;
    cursor: pointer;
    font-size: 14px;
  }

  li.cursor {
    background: var(--hover);
  }

  li.disabled {
    opacity: 0.45;
    cursor: not-allowed;
  }

  li.empty {
    color: var(--fg-muted);
    justify-content: center;
    cursor: default;
  }
  li.empty:hover {
    background: transparent;
  }

  .row {
    display: flex;
    align-items: baseline;
    gap: 10px;
    min-width: 0;
  }

  .group {
    color: var(--fg-muted);
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    font-weight: 600;
  }

  .label {
    color: var(--fg);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .hint {
    color: var(--fg-muted);
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 11px;
    flex-shrink: 0;
  }
</style>
