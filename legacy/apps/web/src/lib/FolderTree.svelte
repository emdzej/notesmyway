<script module lang="ts">
  function stripMd(name: string): string {
    return name.replace(/\.md$/i, '')
  }
</script>

<script lang="ts">
  import type { FileEntry, FileSystem } from '@nmy/core'
  import Self from './FolderTree.svelte'

  type Props = {
    entries: FileEntry[]
    fs: FileSystem
    activePath: string | null
    onOpen: (path: string) => void | Promise<void>
    depth?: number
  }

  let { entries, fs, activePath, onOpen, depth = 0 }: Props = $props()

  let expanded: Record<string, boolean> = $state({})
  let children: Record<string, FileEntry[]> = $state({})

  async function toggleDir(dir: FileEntry) {
    if (expanded[dir.path]) {
      expanded[dir.path] = false
      return
    }
    if (!children[dir.path]) {
      children[dir.path] = await fs.list(dir.path)
    }
    expanded[dir.path] = true
  }
</script>

<ul class="tree" data-depth={depth}>
  {#each entries as entry (entry.path)}
    {@const kids = children[entry.path]}
    {#if entry.kind === 'directory'}
      <li>
        <button
          class="row dir"
          style:padding-left="{8 + depth * 12}px"
          onclick={() => toggleDir(entry)}
        >
          <span class="chev" class:open={expanded[entry.path]}>›</span>
          <span class="label">{entry.name}</span>
        </button>
        {#if expanded[entry.path] && kids}
          <Self entries={kids} {fs} {activePath} {onOpen} depth={depth + 1} />
        {/if}
      </li>
    {:else}
      <li>
        <button
          class="row file"
          class:active={entry.path === activePath}
          style:padding-left="{8 + depth * 12 + 14}px"
          onclick={() => onOpen(entry.path)}
        >
          <span class="label">{stripMd(entry.name)}</span>
        </button>
      </li>
    {/if}
  {/each}
</ul>

<style>
  .tree {
    list-style: none;
    padding: 0;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 1px;
  }

  .row {
    display: flex;
    align-items: center;
    gap: 4px;
    width: 100%;
    text-align: left;
    padding: 4px 8px;
    border-radius: 4px;
    font-size: 13px;
    font-family: inherit;
    color: var(--fg);
    background: transparent;
    border: none;
    cursor: pointer;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .row:hover {
    background: var(--hover);
  }

  .row.file.active {
    background: var(--hover);
    font-weight: 500;
  }

  .row.dir {
    color: var(--fg-muted);
    font-weight: 500;
  }

  .chev {
    display: inline-block;
    width: 10px;
    color: var(--fg-muted);
    transition: transform 0.12s ease;
    font-size: 12px;
  }
  .chev.open {
    transform: rotate(90deg);
  }

  .label {
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
