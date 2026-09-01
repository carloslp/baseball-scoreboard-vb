<svelte:options runes={false} />

<script>
  import { onMount } from 'svelte'
</script>

<svelte:head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
  <title>Baseball Scoreboard</title>
</svelte:head>

<slot />

<style>
  /* ── iOS / Mobile Global Foundations ─────────────────────────── */
  :global(*, *::before, *::after) {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
    touch-action: manipulation;
    -webkit-tap-highlight-color: transparent;
  }

  :global(html) {
    -webkit-text-size-adjust: 100%;
    text-size-adjust: 100%;
    -webkit-overflow-scrolling: touch;
    overscroll-behavior: none;
  }

  :global(body) {
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
    background: #000000;
    color: #ffffff;
    min-height: 100vh;
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
    text-rendering: optimizeLegibility;
    overflow-x: hidden;
    padding-bottom: env(safe-area-inset-bottom, 0px);
    overscroll-behavior-y: contain;
  }

  :global(button) {
    cursor: pointer;
    font-family: inherit;
    touch-action: manipulation;
    -webkit-tap-highlight-color: transparent;
  }

  :global(input, select, textarea) {
    font-family: inherit;
    font-size: 16px;
    -webkit-appearance: none;
    appearance: none;
    -webkit-tap-highlight-color: transparent;
  }

  :global(input[type="date"]),
  :global(input[type="time"]),
  :global(input[type="datetime-local"]),
  :global(input[type="month"]) {
    -webkit-appearance: none;
    appearance: none;
  }

  :global(input[type="color"]) {
    -webkit-appearance: none;
    appearance: none;
    width: 44px;
    height: 44px;
    padding: 0;
    border: none;
    border-radius: 8px;
    cursor: pointer;
    background: transparent;
    overflow: hidden;
  }

  :global(input[type="color"]::-webkit-color-swatch-wrapper) {
    padding: 0;
  }

  :global(input[type="color"]::-webkit-color-swatch) {
    border: none;
    border-radius: 8px;
  }

  :global(input:-webkit-autofill),
  :global(input:-webkit-autofill:hover),
  :global(input:-webkit-autofill:focus) {
    -webkit-text-fill-color: #ffffff;
    -webkit-box-shadow: 0 0 0px 1000px #1a1a2e inset;
    transition: background-color 5000s ease-in-out 0s;
  }

  :global(a) {
    touch-action: manipulation;
    -webkit-tap-highlight-color: transparent;
  }

  :global(img),
  :global(emoji) {
    -webkit-touch-callout: none;
    user-select: none;
  }

  :global(:focus-visible) {
    outline: 2px solid #1a73e8;
    outline-offset: 2px;
  }

  :global(:focus:not(:focus-visible)) {
    outline: none;
  }

  @media (prefers-reduced-motion: reduce) {
    :global(*),
    :global(*::before),
    :global(*::after) {
      animation-duration: 0.01ms !important;
      animation-iteration-count: 1 !important;
      transition-duration: 0.01ms !important;
      scroll-behavior: auto !important;
    }
  }

  @media (max-height: 500px) {
    :global(body) {
      min-height: auto;
    }
  }
</style>