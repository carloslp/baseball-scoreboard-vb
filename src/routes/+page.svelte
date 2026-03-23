<svelte:options runes={false} />

<script>
  import { onMount } from 'svelte'
  import { goto } from '$app/navigation'
  import { supabase } from '$lib/supabase'

  onMount(async () => {
    const { data: { session } } = await supabase.auth.getSession()
    if (session) {
      goto('/dashboard')
    } else {
      goto('/login')
    }
  })
</script>

<div class="loading">
  <div class="spinner"></div>
</div>

<style>
  .loading {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 100vh;
  }

  .spinner {
    width: 40px;
    height: 40px;
    border: 3px solid rgba(255,255,255,0.1);
    border-top-color: #1a73e8;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }
</style>
