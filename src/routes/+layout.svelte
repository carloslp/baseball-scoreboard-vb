<svelte:options runes={false} />

<script>
  import { onMount } from 'svelte'
</script>

<svelte:head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Baseball Scoreboard</title>
</svelte:head>

<slot />

<style>
  :global(*, *::before, *::after) {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
  }

  :global(body) {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
    background: #0f1117;
    color: #e8eaf6;
    min-height: 100vh;
  }

  :global(button) {
    cursor: pointer;
    font-family: inherit;
  }

  :global(input) {
    font-family: inherit;
  }
</style>
