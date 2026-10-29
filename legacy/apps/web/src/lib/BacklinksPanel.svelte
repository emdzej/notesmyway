<script lang="ts">
  import type { Backlink } from '@nmy/core'

  type Props = {
    backlinks: Backlink[]
    onOpen: (path: string) => void
  }

  let { backlinks, onOpen }: Props = $props()
</script>

<aside class="backlinks">
  <header>
    <h2>Backlinks</h2>
    <span class="count">{backlinks.length}</span>
  </header>
  {#if backlinks.length === 0}
    <p class="empty">no backlinks yet</p>
  {:else}
    <ul>
      {#each backlinks as link (link.fromPath)}
        <li>
          <button onclick={() => onOpen(link.fromPath)}>
            <span class="title">{link.fromTitle}</span>
            <span class="path">{link.fromPath.replace(/^\//, '')}</span>
          </button>
        </li>
      {/each}
    </ul>
  {/if}
</aside>

<style>
  .backlinks {
    border-top: 1px solid var(--border);
    padding: 12px 18px 16px;
    background: var(--bg);
    color: var(--fg);
    font-size: 13px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    max-height: 30%;
    overflow: auto;
  }

  header {
    display: flex;
    align-items: baseline;
    gap: 8px;
  }

  h2 {
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--fg-muted);
    margin: 0;
  }

  .count {
    color: var(--fg-muted);
    font-size: 11px;
  }

  .empty {
    color: var(--fg-muted);
    margin: 0;
    font-size: 12px;
  }

  ul {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  button {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 2px;
    width: 100%;
    text-align: left;
    background: transparent;
    border: none;
    padding: 6px 8px;
    border-radius: 4px;
    cursor: pointer;
    color: inherit;
    font: inherit;
  }

  button:hover {
    background: var(--hover);
  }

  .title {
    color: var(--fg);
  }

  .path {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    color: var(--fg-muted);
    font-size: 11px;
  }
</style>
