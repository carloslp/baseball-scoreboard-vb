<svelte:options runes={false} />

<script>
  import { onMount, onDestroy } from 'svelte'
  import { goto } from '$app/navigation'
  import { supabase } from '$lib/supabase'

  let session = null
  let match = null
  let loading = true
  let saving = false
  let error = ''
  let obsUrlCopied = false

  let nameDebounceTimer = null

  $: obsUrl = match ? `${typeof window !== 'undefined' ? window.location.origin : ''}/obs/${match.user_obs_token}` : ''

  onMount(async () => {
    const { data: { session: s } } = await supabase.auth.getSession()
    if (!s) {
      goto('/login')
      return
    }
    session = s
    await loadActiveMatch()

    supabase.auth.onAuthStateChange((event, s) => {
      if (event === 'SIGNED_OUT') goto('/login')
    })
  })

  async function loadActiveMatch() {
    loading = true
    error = ''
    const { data, error: err } = await supabase
      .from('matches')
      .select('*')
      .eq('user_id', session.user.id)
      .eq('is_active', true)
      .single()

    if (err && err.code !== 'PGRST116') {
      error = err.message
    } else {
      match = data || null
    }
    loading = false
  }

  async function createNewMatch() {
    if (!session) return
    saving = true
    error = ''

    await supabase
      .from('matches')
      .update({ is_active: false })
      .eq('user_id', session.user.id)

    const token = crypto.randomUUID().replace(/-/g, '')

    const { data, error: err } = await supabase
      .from('matches')
      .insert({
        user_id: session.user.id,
        user_obs_token: token,
        is_active: true
      })
      .select()
      .single()

    if (err) {
      error = err.message
    } else {
      match = data
    }
    saving = false
  }

  async function updateMatch(updates) {
    if (!match) return
    const { data, error: err } = await supabase
      .from('matches')
      .update(updates)
      .eq('id', match.id)
      .select()
      .single()

    if (err) {
      error = err.message
    } else {
      match = data
    }
  }

  async function adjustScore(team, delta) {
    const field = team === 'home' ? 'home_score' : 'away_score'
    const current = match[field]
    const newVal = Math.max(0, current + delta)
    await updateMatch({ [field]: newVal })
  }

  async function addBall() {
    if (!match) return
    if (match.balls >= 3) {
      await updateMatch({ balls: 0 })
    } else {
      await updateMatch({ balls: match.balls + 1 })
    }
  }

  async function addStrike() {
    if (!match) return
    if (match.strikes >= 2) {
      await updateMatch({ strikes: 0, balls: 0 })
    } else {
      await updateMatch({ strikes: match.strikes + 1 })
    }
  }

  async function clearCount() {
    await updateMatch({ balls: 0, strikes: 0 })
  }

  async function addOut() {
    if (!match) return
    if (match.outs >= 2) {
      let newInningHalf = match.inning_half
      let newInning = match.inning
      if (match.inning_half === 'top') {
        newInningHalf = 'bottom'
      } else {
        newInningHalf = 'top'
        newInning = match.inning + 1
      }
      await updateMatch({
        outs: 0,
        inning: newInning,
        inning_half: newInningHalf,
        balls: 0,
        strikes: 0,
        base1: false,
        base2: false,
        base3: false
      })
    } else {
      await updateMatch({ outs: match.outs + 1, balls: 0, strikes: 0 })
    }
  }

  async function adjustInning(delta) {
    const newInning = Math.max(1, match.inning + delta)
    await updateMatch({ inning: newInning })
  }

  async function toggleBase(baseNum) {
    if (!match) return
    const field = `base${baseNum}`
    await updateMatch({ [field]: !match[field] })
  }

  async function clearBases() {
    await updateMatch({ base1: false, base2: false, base3: false })
  }

  function onTeamNameChange(field, value) {
    if (match) match[field] = value
    clearTimeout(nameDebounceTimer)
    nameDebounceTimer = setTimeout(async () => {
      await updateMatch({ [field]: value })
    }, 600)
  }

  async function onColorChange(field, value) {
    await updateMatch({ [field]: value })
  }

  async function copyObsUrl() {
    try {
      await navigator.clipboard.writeText(obsUrl)
      obsUrlCopied = true
      setTimeout(() => obsUrlCopied = false, 2000)
    } catch (e) {
      error = 'Failed to copy URL'
    }
  }

  async function logout() {
    await supabase.auth.signOut()
    goto('/login')
  }

  onDestroy(() => {
    clearTimeout(nameDebounceTimer)
  })
</script>

<div class="dashboard">
  <header>
    <div class="header-left">
      <span class="logo">⚾</span>
      <h1>Scoreboard</h1>
    </div>
    <div class="header-right">
      {#if session}
        <span class="user-email">{session.user.email}</span>
      {/if}
      <button class="btn-logout" on:click={logout}>Sign Out</button>
    </div>
  </header>

  <main>
    {#if loading}
      <div class="center">
        <div class="spinner"></div>
      </div>
    {:else if error}
      <div class="error-banner">{error}</div>
    {/if}

    {#if !loading}
      <div class="top-bar">
        <button class="btn-new" on:click={createNewMatch} disabled={saving}>
          {saving ? '…' : '+ New Match'}
        </button>
        {#if match}
          <div class="obs-row">
            <span class="obs-label">OBS URL:</span>
            <code class="obs-url">{obsUrl}</code>
            <button class="btn-copy" on:click={copyObsUrl}>
              {obsUrlCopied ? '✓ Copied' : '📋 Copy'}
            </button>
            <a href={obsUrl} target="_blank" rel="noopener" class="btn-preview">Preview</a>
          </div>
        {/if}
      </div>

      {#if match}
        <div class="scoreboard-grid">

          <section class="card score-card">
            <h2>Score</h2>
            <div class="teams">
              <div class="team" style="--team-color: {match.away_team_color}">
                <div class="team-inputs">
                  <input
                    type="color"
                    value={match.away_team_color}
                    on:change={(e) => onColorChange('away_team_color', e.target.value)}
                    class="color-picker"
                    title="Away team color"
                  />
                  <input
                    type="text"
                    value={match.away_team_name}
                    on:input={(e) => onTeamNameChange('away_team_name', e.target.value)}
                    class="team-name-input"
                    maxlength="20"
                    placeholder="AWAY"
                  />
                </div>
                <div class="score-control">
                  <button class="score-btn minus" on:click={() => adjustScore('away', -1)} disabled={match.away_score <= 0}>−</button>
                  <span class="score-display">{match.away_score}</span>
                  <button class="score-btn plus" on:click={() => adjustScore('away', 1)}>+</button>
                </div>
              </div>

              <div class="vs-divider">VS</div>

              <div class="team" style="--team-color: {match.home_team_color}">
                <div class="team-inputs">
                  <input
                    type="color"
                    value={match.home_team_color}
                    on:change={(e) => onColorChange('home_team_color', e.target.value)}
                    class="color-picker"
                    title="Home team color"
                  />
                  <input
                    type="text"
                    value={match.home_team_name}
                    on:input={(e) => onTeamNameChange('home_team_name', e.target.value)}
                    class="team-name-input"
                    maxlength="20"
                    placeholder="HOME"
                  />
                </div>
                <div class="score-control">
                  <button class="score-btn minus" on:click={() => adjustScore('home', -1)} disabled={match.home_score <= 0}>−</button>
                  <span class="score-display">{match.home_score}</span>
                  <button class="score-btn plus" on:click={() => adjustScore('home', 1)}>+</button>
                </div>
              </div>
            </div>
          </section>

          <section class="card inning-card">
            <div class="inning-bases-row">
              <div class="inning-section">
                <h2>Inning</h2>
                <div class="inning-control">
                  <button class="btn-icon" on:click={() => adjustInning(-1)} disabled={match.inning <= 1}>▼</button>
                  <div class="inning-display">
                    <div class="inning-half-indicator">
                      <button
                        class="half-btn {match.inning_half === 'top' ? 'active' : ''}"
                        on:click={() => updateMatch({ inning_half: 'top' })}
                        title="Top of inning"
                      >▲</button>
                      <button
                        class="half-btn {match.inning_half === 'bottom' ? 'active' : ''}"
                        on:click={() => updateMatch({ inning_half: 'bottom' })}
                        title="Bottom of inning"
                      >▼</button>
                    </div>
                    <span class="inning-number">{match.inning}</span>
                  </div>
                  <button class="btn-icon" on:click={() => adjustInning(1)}>▲</button>
                </div>
                <div class="inning-label">{match.inning_half === 'top' ? 'TOP' : 'BOTTOM'} of {match.inning}</div>
              </div>

              <div class="bases-section">
                <h2>Bases</h2>
                <div class="bases-buttons">
                  <div class="bases-row-top">
                    <button
                      class="base-btn-ui base2 {match.base2 ? 'occupied' : ''}"
                      on:click={() => toggleBase(2)}
                      aria-label="2nd base"
                      title="2nd base"
                    >2B</button>
                  </div>
                  <div class="bases-row-mid">
                    <button
                      class="base-btn-ui base3 {match.base3 ? 'occupied' : ''}"
                      on:click={() => toggleBase(3)}
                      aria-label="3rd base"
                      title="3rd base"
                    >3B</button>
                    <div class="bases-gap"></div>
                    <button
                      class="base-btn-ui base1 {match.base1 ? 'occupied' : ''}"
                      on:click={() => toggleBase(1)}
                      aria-label="1st base"
                      title="1st base"
                    >1B</button>
                  </div>
                </div>
                <button class="btn-clear" on:click={clearBases}>Clear Bases</button>
              </div>
            </div>
          </section>

          <section class="card count-card">
            <h2>Count</h2>
            <div class="count-grid">
              <div class="count-item">
                <span class="count-label">Balls</span>
                <button class="count-btn balls" on:click={addBall}>
                  <div class="pip-row">
                    {#each Array(4) as _, i}
                      <span class="pip {i < match.balls ? 'on' : 'off'}"></span>
                    {/each}
                  </div>
                  <span class="count-number">{match.balls}</span>
                </button>
              </div>
              <div class="count-item">
                <span class="count-label">Strikes</span>
                <button class="count-btn strikes" on:click={addStrike}>
                  <div class="pip-row">
                    {#each Array(3) as _, i}
                      <span class="pip {i < match.strikes ? 'on' : 'off'}"></span>
                    {/each}
                  </div>
                  <span class="count-number">{match.strikes}</span>
                </button>
              </div>
              <div class="count-item">
                <span class="count-label">Outs</span>
                <button class="count-btn outs" on:click={addOut}>
                  <div class="pip-row">
                    {#each Array(3) as _, i}
                      <span class="pip {i < match.outs ? 'on' : 'off'}"></span>
                    {/each}
                  </div>
                  <span class="count-number">{match.outs}</span>
                </button>
              </div>
            </div>
            <button class="btn-clear" on:click={clearCount}>Clear Count</button>
          </section>

        </div>
      {:else}
        <div class="no-match">
          <div class="no-match-icon">⚾</div>
          <p>No active match. Create a new match to get started.</p>
          <button class="btn-new-large" on:click={createNewMatch} disabled={saving}>
            {saving ? 'Creating…' : '+ New Match'}
          </button>
        </div>
      {/if}
    {/if}
  </main>
</div>

<style>
  .dashboard {
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    background: #0f1117;
  }

  header {
    background: #1e2330;
    border-bottom: 1px solid rgba(255,255,255,0.08);
    padding: 0.75rem 1.5rem;
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-shrink: 0;
  }

  .header-left {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .logo {
    font-size: 1.5rem;
  }

  h1 {
    font-size: 1.25rem;
    font-weight: 700;
    color: #fff;
  }

  .header-right {
    display: flex;
    align-items: center;
    gap: 1rem;
  }

  .user-email {
    color: #8b8fa8;
    font-size: 0.85rem;
  }

  .btn-logout {
    background: rgba(229, 57, 53, 0.15);
    border: 1px solid rgba(229, 57, 53, 0.3);
    color: #ff6b6b;
    border-radius: 6px;
    padding: 0.4rem 0.875rem;
    font-size: 0.85rem;
    transition: background 0.2s;
  }

  .btn-logout:hover {
    background: rgba(229, 57, 53, 0.25);
  }

  main {
    flex: 1;
    padding: 1.5rem;
    max-width: 1200px;
    margin: 0 auto;
    width: 100%;
  }

  .center {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 200px;
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

  .error-banner {
    background: rgba(229, 57, 53, 0.15);
    border: 1px solid rgba(229, 57, 53, 0.4);
    color: #ff6b6b;
    padding: 0.75rem 1rem;
    border-radius: 8px;
    margin-bottom: 1rem;
    font-size: 0.875rem;
  }

  .top-bar {
    display: flex;
    align-items: center;
    gap: 1rem;
    margin-bottom: 1.5rem;
    flex-wrap: wrap;
  }

  .btn-new {
    background: #1a73e8;
    color: #fff;
    border: none;
    border-radius: 8px;
    padding: 0.625rem 1.25rem;
    font-size: 0.95rem;
    font-weight: 600;
    min-height: 44px;
    transition: background 0.2s;
    white-space: nowrap;
  }

  .btn-new:hover:not(:disabled) {
    background: #1557b0;
  }

  .btn-new:disabled {
    opacity: 0.6;
  }

  .obs-row {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    background: #1e2330;
    border: 1px solid rgba(255,255,255,0.08);
    border-radius: 8px;
    padding: 0.5rem 0.875rem;
    flex: 1;
    min-width: 0;
    flex-wrap: wrap;
  }

  .obs-label {
    color: #8b8fa8;
    font-size: 0.8rem;
    white-space: nowrap;
    font-weight: 600;
  }

  .obs-url {
    font-family: monospace;
    font-size: 0.8rem;
    color: #63b3ed;
    flex: 1;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .btn-copy {
    background: rgba(26, 115, 232, 0.15);
    border: 1px solid rgba(26, 115, 232, 0.3);
    color: #63b3ed;
    border-radius: 6px;
    padding: 0.3rem 0.75rem;
    font-size: 0.8rem;
    white-space: nowrap;
    transition: background 0.2s;
    min-height: 32px;
  }

  .btn-copy:hover {
    background: rgba(26, 115, 232, 0.25);
  }

  .btn-preview {
    background: rgba(26, 115, 232, 0.1);
    border: 1px solid rgba(26, 115, 232, 0.2);
    color: #63b3ed;
    border-radius: 6px;
    padding: 0.3rem 0.75rem;
    font-size: 0.8rem;
    text-decoration: none;
    white-space: nowrap;
    transition: background 0.2s;
    min-height: 32px;
    display: flex;
    align-items: center;
  }

  .btn-preview:hover {
    background: rgba(26, 115, 232, 0.2);
  }

  .scoreboard-grid {
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    gap: 1rem;
    align-items: start;
  }

  @media (max-width: 1024px) and (min-width: 769px) {
    .scoreboard-grid {
      grid-template-columns: 1fr 1fr;
    }
    .score-card {
      grid-column: 1 / 3;
    }
    .inning-card {
      grid-column: 1 / 2;
    }
    .count-card {
      grid-column: 2 / 3;
    }
  }

  @media (max-width: 768px) {
    .scoreboard-grid {
      grid-template-columns: 1fr;
    }
  }

  .card {
    background: #1e2330;
    border: 1px solid rgba(255,255,255,0.08);
    border-radius: 12px;
    padding: 1.5rem;
  }

  .card h2 {
    font-size: 0.8rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    color: #8b8fa8;
    margin-bottom: 1.25rem;
  }

  .score-card {
    grid-column: 1 / 2;
  }

  .teams {
    display: flex;
    align-items: center;
    gap: 1rem;
  }

  .team {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .team-inputs {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .color-picker {
    width: 36px;
    height: 36px;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    padding: 2px;
    background: rgba(255,255,255,0.1);
    flex-shrink: 0;
  }

  .team-name-input {
    background: rgba(255,255,255,0.05);
    border: 1px solid rgba(255,255,255,0.1);
    border-radius: 6px;
    padding: 0.4rem 0.6rem;
    color: var(--team-color, #fff);
    font-size: 0.95rem;
    font-weight: 700;
    text-transform: uppercase;
    width: 100%;
    outline: none;
    transition: border-color 0.2s;
  }

  .team-name-input:focus {
    border-color: rgba(255,255,255,0.3);
  }

  .score-control {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .score-btn {
    width: 44px;
    height: 44px;
    border-radius: 8px;
    border: 1px solid rgba(255,255,255,0.15);
    background: rgba(255,255,255,0.05);
    color: #fff;
    font-size: 1.4rem;
    font-weight: 700;
    line-height: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: background 0.15s;
  }

  .score-btn:hover:not(:disabled) {
    background: rgba(255,255,255,0.12);
  }

  .score-btn:disabled {
    opacity: 0.3;
  }

  .score-display {
    font-size: 2.5rem;
    font-weight: 900;
    color: #fff;
    min-width: 3rem;
    text-align: center;
    font-variant-numeric: tabular-nums;
  }

  .vs-divider {
    color: #4a5068;
    font-size: 0.75rem;
    font-weight: 700;
    padding: 0 0.25rem;
  }

  .inning-card {
    text-align: center;
  }

  .inning-bases-row {
    display: flex;
    gap: 1.5rem;
    align-items: flex-start;
    justify-content: center;
  }

  .inning-section {
    display: flex;
    flex-direction: column;
    align-items: center;
    flex: 0 0 auto;
  }

  .bases-section {
    display: flex;
    flex-direction: column;
    align-items: center;
    flex: 0 0 auto;
  }

  .inning-control {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 0.75rem;
    margin-bottom: 0.75rem;
  }

  .btn-icon {
    width: 44px;
    height: 44px;
    border-radius: 8px;
    border: 1px solid rgba(255,255,255,0.1);
    background: rgba(255,255,255,0.05);
    color: #fff;
    font-size: 1rem;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: background 0.15s;
  }

  .btn-icon:hover:not(:disabled) {
    background: rgba(255,255,255,0.1);
  }

  .btn-icon:disabled {
    opacity: 0.3;
  }

  .inning-display {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .inning-half-indicator {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .half-btn {
    background: none;
    border: 1px solid rgba(255,255,255,0.1);
    border-radius: 4px;
    color: #4a5068;
    font-size: 0.6rem;
    width: 24px;
    height: 22px;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: all 0.15s;
  }

  .half-btn.active {
    background: rgba(26, 115, 232, 0.2);
    border-color: #1a73e8;
    color: #63b3ed;
  }

  .inning-number {
    font-size: 3.5rem;
    font-weight: 900;
    color: #fff;
    line-height: 1;
    font-variant-numeric: tabular-nums;
    min-width: 2.5rem;
    display: inline-block;
    text-align: center;
  }

  .inning-label {
    font-size: 0.85rem;
    color: #8b8fa8;
    font-weight: 600;
    letter-spacing: 0.05em;
  }

  .bases-buttons {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.5rem;
    margin-bottom: 0.75rem;
  }

  .bases-row-top {
    display: flex;
    justify-content: center;
  }

  .bases-row-mid {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .bases-gap {
    width: 56px;
  }

  .base-btn-ui {
    width: 56px;
    height: 56px;
    border-radius: 8px;
    font-size: 0.85rem;
    font-weight: 800;
    letter-spacing: 0.05em;
    border: 2px solid;
    transition: background 0.15s, border-color 0.15s, transform 0.1s;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
  }

  .base-btn-ui:active {
    transform: scale(0.93);
  }

  /* 1st base — green */
  .base-btn-ui.base1 {
    border-color: rgba(74, 222, 128, 0.35);
    background: rgba(74, 222, 128, 0.06);
    color: rgba(74, 222, 128, 0.55);
  }
  .base-btn-ui.base1:hover {
    border-color: rgba(74, 222, 128, 0.6);
    background: rgba(74, 222, 128, 0.14);
    color: #4ade80;
  }
  .base-btn-ui.base1.occupied {
    background: #4ade80;
    border-color: #4ade80;
    color: #0f1117;
  }
  .base-btn-ui.base1.occupied:hover {
    background: #22c55e;
    border-color: #22c55e;
  }

  /* 2nd base — gold */
  .base-btn-ui.base2 {
    border-color: rgba(240, 192, 64, 0.35);
    background: rgba(240, 192, 64, 0.06);
    color: rgba(240, 192, 64, 0.55);
  }
  .base-btn-ui.base2:hover {
    border-color: rgba(240, 192, 64, 0.6);
    background: rgba(240, 192, 64, 0.14);
    color: #f0c040;
  }
  .base-btn-ui.base2.occupied {
    background: #f0c040;
    border-color: #f0c040;
    color: #0f1117;
  }
  .base-btn-ui.base2.occupied:hover {
    background: #d4a900;
    border-color: #d4a900;
  }

  /* 3rd base — blue */
  .base-btn-ui.base3 {
    border-color: rgba(99, 179, 237, 0.35);
    background: rgba(99, 179, 237, 0.06);
    color: rgba(99, 179, 237, 0.55);
  }
  .base-btn-ui.base3:hover {
    border-color: rgba(99, 179, 237, 0.6);
    background: rgba(99, 179, 237, 0.14);
    color: #63b3ed;
  }
  .base-btn-ui.base3.occupied {
    background: #63b3ed;
    border-color: #63b3ed;
    color: #0f1117;
  }
  .base-btn-ui.base3.occupied:hover {
    background: #3b9de0;
    border-color: #3b9de0;
  }

  .count-card {
    grid-column: 3 / 4;
  }

  @media (max-width: 768px) {
    .count-card {
      grid-column: 1;
    }
  }

  .count-grid {
    display: flex;
    gap: 0.75rem;
    margin-bottom: 1rem;
  }

  .count-item {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
    align-items: center;
  }

  .count-label {
    font-size: 0.7rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: #8b8fa8;
  }

  .count-btn {
    background: rgba(255,255,255,0.05);
    border: 1px solid rgba(255,255,255,0.1);
    border-radius: 10px;
    padding: 0.75rem 0.5rem;
    width: 100%;
    min-height: 80px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 0.5rem;
    transition: background 0.15s, border-color 0.15s;
  }

  .count-btn:hover {
    background: rgba(255,255,255,0.09);
    border-color: rgba(255,255,255,0.2);
  }

  .count-btn:active {
    transform: scale(0.97);
  }

  .count-btn.balls:hover { border-color: rgba(74, 222, 128, 0.4); }
  .count-btn.strikes:hover { border-color: rgba(251, 191, 36, 0.4); }
  .count-btn.outs:hover { border-color: rgba(248, 113, 113, 0.4); }

  .pip-row {
    display: flex;
    gap: 4px;
  }

  .pip {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    border: 2px solid rgba(255,255,255,0.2);
  }

  .count-btn.balls .pip.on { background: #4ade80; border-color: #4ade80; }
  .count-btn.strikes .pip.on { background: #fbbf24; border-color: #fbbf24; }
  .count-btn.outs .pip.on { background: #f87171; border-color: #f87171; }

  .count-number {
    font-size: 1.75rem;
    font-weight: 900;
    color: #fff;
    line-height: 1;
    font-variant-numeric: tabular-nums;
  }

  @media (min-width: 769px) and (max-width: 1024px) {
    .score-btn,
    .btn-icon,
    .count-btn {
      min-height: 52px;
    }

    .score-btn {
      width: 52px;
      height: 52px;
    }

    .btn-icon {
      width: 52px;
      height: 52px;
    }

    .base-btn-ui {
      width: 64px;
      height: 64px;
      font-size: 0.95rem;
    }

    .bases-gap {
      width: 64px;
    }

    .inning-number {
      font-size: 4rem;
    }

    .score-display {
      font-size: 3rem;
    }
  }

  .btn-clear {
    width: 100%;
    background: rgba(255,255,255,0.05);
    border: 1px solid rgba(255,255,255,0.1);
    color: #8b8fa8;
    border-radius: 8px;
    padding: 0.6rem;
    font-size: 0.85rem;
    font-weight: 600;
    min-height: 44px;
    transition: background 0.15s, color 0.15s;
  }

  .btn-clear:hover {
    background: rgba(255,255,255,0.09);
    color: #e8eaf6;
  }

  .no-match {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 1rem;
    padding: 4rem 2rem;
    text-align: center;
  }

  .no-match-icon {
    font-size: 4rem;
    opacity: 0.3;
  }

  .no-match p {
    color: #8b8fa8;
    font-size: 1rem;
  }

  .btn-new-large {
    background: #1a73e8;
    color: #fff;
    border: none;
    border-radius: 10px;
    padding: 0.875rem 2rem;
    font-size: 1.1rem;
    font-weight: 700;
    min-height: 52px;
    transition: background 0.2s;
  }

  .btn-new-large:hover:not(:disabled) {
    background: #1557b0;
  }

  .btn-new-large:disabled {
    opacity: 0.6;
  }
</style>
