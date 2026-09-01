<svelte:options runes={false} />

<script>
  import { supabase } from '$lib/supabase'
  import { goto } from '$app/navigation'
  import { onMount } from 'svelte'

  let email = ''
  let password = ''
  let loading = false
  let error = ''
  let mode = 'login'
  let successMessage = ''

  onMount(async () => {
    const { data: { session } } = await supabase.auth.getSession()
    if (session) goto('/dashboard')
  })

  async function handleSubmit() {
    loading = true
    error = ''
    successMessage = ''

    if (mode === 'login') {
      const { error: err } = await supabase.auth.signInWithPassword({ email, password })
      if (err) {
        error = err.message
      } else {
        goto('/dashboard')
      }
    } else {
      const { error: err } = await supabase.auth.signUp({ email, password })
      if (err) {
        error = err.message
      } else {
        successMessage = 'Account created! Check your email to confirm, then log in.'
        mode = 'login'
      }
    }

    loading = false
  }

  function toggleMode() {
    mode = mode === 'login' ? 'register' : 'login'
    error = ''
    successMessage = ''
  }
</script>

<div class="page">
  <div class="card">
    <div class="logo">⚾</div>
    <h1>Baseball Scoreboard</h1>
    <p class="subtitle">{mode === 'login' ? 'Sign in to manage your scoreboard' : 'Create a new account'}</p>

    <form on:submit|preventDefault={handleSubmit}>
      <div class="field">
        <label for="email">Email</label>
        <input
          id="email"
          type="email"
          inputmode="email"
          bind:value={email}
          placeholder="you@example.com"
          required
          disabled={loading}
          autocomplete="username"
        />
      </div>

      <div class="field">
        <label for="password">Password</label>
        <input
          id="password"
          type="password"
          bind:value={password}
          placeholder="••••••••"
          required
          disabled={loading}
          minlength="6"
          autocomplete="current-password"
        />
      </div>

      {#if error}
        <div class="error">{error}</div>
      {/if}

      {#if successMessage}
        <div class="success">{successMessage}</div>
      {/if}

      <button type="submit" class="btn-primary" disabled={loading}>
        {#if loading}
          <span class="spinner-sm"></span>
        {:else}
          {mode === 'login' ? 'Sign In' : 'Create Account'}
        {/if}
      </button>
    </form>

    <button class="btn-toggle" on:click={toggleMode}>
      {mode === 'login' ? "Don't have an account? Register" : 'Already have an account? Sign In'}
    </button>
  </div>
</div>

<style>
  .page {
    min-height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    background: #000000;
    padding: 1rem;
    padding-bottom: max(1rem, env(safe-area-inset-bottom, 1rem));
  }

  .card {
    background: #111111;
    border: 1px solid rgba(255,255,255,0.15);
    border-radius: 16px;
    padding: 2rem;
    width: 100%;
    max-width: 420px;
    box-shadow: 0 20px 60px rgba(0,0,0,0.6);
  }

  .logo {
    font-size: 3rem;
    text-align: center;
    margin-bottom: 0.5rem;
  }

  h1 {
    text-align: center;
    font-size: 1.5rem;
    font-weight: 800;
    color: #ffffff;
    margin-bottom: 0.25rem;
  }

  .subtitle {
    text-align: center;
    color: #aaaaaa;
    font-size: 0.9rem;
    margin-bottom: 2rem;
  }

  form {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
  }

  label {
    font-size: 0.85rem;
    color: #cccccc;
    font-weight: 600;
  }

  input {
    background: #1a1a1a;
    border: 1px solid rgba(255,255,255,0.2);
    border-radius: 8px;
    padding: 0.75rem 1rem;
    color: #ffffff;
    font-size: 1rem;
    outline: none;
    transition: border-color 0.2s;
  }

  input:focus {
    border-color: #FFE600;
  }

  input::placeholder {
    color: #555555;
  }

  input:disabled {
    opacity: 0.6;
  }

  .error {
    background: rgba(229, 57, 53, 0.15);
    border: 1px solid rgba(229, 57, 53, 0.4);
    color: #ff6b6b;
    padding: 0.75rem 1rem;
    border-radius: 8px;
    font-size: 0.875rem;
  }

  .success {
    background: rgba(26, 115, 232, 0.15);
    border: 1px solid rgba(26, 115, 232, 0.4);
    color: #63b3ed;
    padding: 0.75rem 1rem;
    border-radius: 8px;
    font-size: 0.875rem;
  }

  .btn-primary {
    background: #1a73e8;
    color: #fff;
    border: none;
    border-radius: 8px;
    padding: 0.875rem;
    font-size: 1rem;
    font-weight: 600;
    transition: background 0.2s, transform 0.1s;
    min-height: 48px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 0.5rem;
  }

  .btn-primary:hover:not(:disabled) {
    background: #1557b0;
  }

  .btn-primary:active:not(:disabled) {
    transform: scale(0.98);
  }

  .btn-primary:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .btn-toggle {
    background: none;
    border: none;
    color: #1a73e8;
    font-size: 0.875rem;
    margin-top: 1.25rem;
    width: 100%;
    text-align: center;
    padding: 0.5rem;
    border-radius: 6px;
    transition: background 0.2s;
  }

  .btn-toggle:hover {
    background: rgba(26, 115, 232, 0.1);
  }

  .spinner-sm {
    width: 18px;
    height: 18px;
    border: 2px solid rgba(255,255,255,0.3);
    border-top-color: #fff;
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  /* ── Small mobile screens ──────────────────────────── */
  @media (max-width: 375px) {
    .page {
      padding: 0.75rem;
      padding-bottom: max(0.75rem, env(safe-area-inset-bottom, 0.75rem));
    }

    .card {
      padding: 1.5rem;
      border-radius: 12px;
    }

    h1 {
      font-size: 1.25rem;
    }

    .logo {
      font-size: 2.5rem;
    }

    .subtitle {
      font-size: 0.85rem;
      margin-bottom: 1.5rem;
    }

    form {
      gap: 0.875rem;
    }

    .btn-toggle {
      font-size: 0.8rem;
      margin-top: 1rem;
      padding: 0.4rem;
    }
  }
</style>
