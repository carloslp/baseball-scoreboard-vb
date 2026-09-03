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
  let previousMatch = null
  let flash = {}
  let flashTimer = null
  let newBatterName = ''
  let battersList = []
  let atBatStats = []
  let loadingAtBatStats = false
  let atBatStatsError = ''

  const AT_BAT_STATS_URL = 'https://script.google.com/macros/s/AKfycby7mLKmo5tYeyah3g75xA9FS48FPDbq6SJMkFDPErFi9dgrNAvlOEeapwTQ2fZTlHZg/exec?token=dads-12w1-dd3f-da1g&id=1r56WDn_pgZwoAHiiWmeaadUe1hepXC3Mo4t4PWwwfbQ&hoja=AVG-Activo'

  $: obsUrl = match ? `${typeof window !== 'undefined' ? window.location.origin : ''}/obs/${match.user_obs_token}` : ''
  $: battersList = Array.isArray(match?.batters_list)
    ? match.batters_list.filter((name) => typeof name === 'string' && name.trim())
    : []

  onMount(async () => {
    const { data: { session: s } } = await supabase.auth.getSession()
    if (!s) {
      goto('/login')
      return
    }
    session = s
    await Promise.all([loadActiveMatch(), loadAtBatStats()])

    supabase.auth.onAuthStateChange((event, s) => {
      if (event === 'SIGNED_OUT') goto('/login')
    })
  })

  /** @param {string | null | undefined} name */
  function getShortBatterName(name) {
    const parts = (name || '').trim().replace(/\s+/g, ' ').split(' ').filter(Boolean)
    
    if (parts.length === 0) return ''
    if (parts.length === 1) return parts[0]
    if (parts.length === 2) return `${parts[0]} ${parts[1]}`
    
    // Si tiene 4 partes (Ej: "Julio Cesar Urias Acosta") -> parts[0] + parts[2]
    // Si tiene 3 partes (Ej: "Julio Urias Acosta") -> parts[0] + parts[1]
    if (parts.length >= 3) {
      // Toma el primer nombre y el penúltimo elemento (primer apellido)
      return `${parts[0]} ${parts[parts.length - 2]}`
    }
  }

  async function loadAtBatStats() {
    loadingAtBatStats = true
    atBatStatsError = ''

    try {
      const response = await fetch(AT_BAT_STATS_URL)
      const payload = await response.json()
      const data = Array.isArray(payload?.data) ? payload.data : []
      atBatStats = data
        .map((item) => {
          const fullName = typeof item?.Nombre === 'string' ? item.Nombre.trim() : ''
          const shortName = getShortBatterName(fullName)
          if (!shortName) return null
          return {
            fullName,
            shortName,
            AB: item?.AB ?? 0,
            H: item?.H ?? 0,
            HR: item?.HR ?? 0,
            K: item?.K ?? 0,
            AVG: item?.AVG ?? '.000'
          }
        })
        .filter(Boolean)
    } catch (err) {
      atBatStats = []
      atBatStatsError = 'No se pudieron cargar las estadísticas de turno al bat.'
    } finally {
      loadingAtBatStats = false
    }
  }

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
    previousMatch = structuredClone(match)
    const { data, error: err } = await supabase
      .from('matches')
      .update(updates)
      .eq('id', match.id)
      .select()
      .single()

    if (err) {
      error = err.message
      previousMatch = null
    } else {
      match = data
      triggerFlash(Object.keys(updates))
    }
  }

  function triggerFlash(fields) {
    const newFlash = {}
    for (const key of fields) {
      newFlash[key] = true
    }
    flash = newFlash
    clearTimeout(flashTimer)
    flashTimer = setTimeout(() => { flash = {} }, 200)
  }

  // Fields that identify the record and must not be overwritten by undo.
  // Any future non-state columns (created_at, updated_at, etc.) should be
  // added here as well.
  const UNDO_EXCLUDED_FIELDS = new Set(['id', 'user_id', 'user_obs_token', 'is_active'])

  async function undo() {
    if (!previousMatch || !match) return
    const prevData = previousMatch
    previousMatch = null
    const stateFields = Object.fromEntries(
      Object.entries(prevData).filter(([k]) => !UNDO_EXCLUDED_FIELDS.has(k))
    )
    const { data, error: err } = await supabase
      .from('matches')
      .update(stateFields)
      .eq('id', match.id)
      .select()
      .single()
    if (err) {
      error = err.message
    } else {
      match = data
      triggerFlash(Object.keys(stateFields))
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
      // 4th ball = walk: reset count
      await updateMatch({ balls: 0, strikes: 0 })
    } else {
      await updateMatch({ balls: match.balls + 1 })
    }
  }

  async function addStrike() {
    if (!match) return
    if (match.strikes >= 2) {
      // 3rd strike = strikeout: add an out (resets count and advances inning if needed)
      await addOut()
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

  async function clearAtBatText() {
    await updateMatch({ at_bat_text: null })
  }

  async function addBatterToList() {
    if (!match) return
    const value = (newBatterName || '').trim()
    if (!value) return
    await updateMatch({ batters_list: [...battersList, value] })
    newBatterName = ''
  }

  async function removeBatterFromList(index) {
    if (!match) return
    await updateMatch({ batters_list: battersList.filter((_, i) => i !== index) })
  }

  async function setAtBatBatter(name) {
    if (!match) return
    const value = (name || '').trim()
    await updateMatch({
      at_bat_text: value || null,
      at_bat_counter: (match.at_bat_counter || 0) + 1
    })
  }

  async function triggerHomeRun() {
    if (!match) return
    await updateMatch({ home_run_counter: (match.home_run_counter || 0) + 1 })
  }

  function isValidBannerConfig(value) {
    const lines = (value || '').replace(/\r\n/g, '\n').split('\n')
    return lines.every((line) => {
      const trimmed = line.trim()
      return !trimmed || trimmed.startsWith('https://')
    })
  }

  /** @param {number} number */
  function getOrdinal(number) {
    const lastTwoDigits = number % 100
    if (lastTwoDigits >= 11 && lastTwoDigits <= 13) return number + 'th'
    const lastDigit = number % 10
    return number + (['th', 'st', 'nd', 'rd'][lastDigit] || 'th')
  }

  /** @param {string | null | undefined} name */
  function getTeamParts(name) {
    const normalized = (name || '').trim().replace(/\s+/g, ' ')
    if (!normalized) {
      return { short: '---', long: 'TEAM' }
    }

    const words = normalized.split(' ')
    const firstWord = words[0]
    if (words.length > 1 && /^[A-Za-z0-9]{2,4}$/.test(firstWord)) {
      return {
        short: firstWord.toUpperCase(),
        long: words.slice(1).join(' ').toUpperCase()
      }
    }

    const filteredWords = words.filter((word) => !/^(de|del|la|las|los|the|and|y)$/i.test(word))
    const sourceWords = filteredWords.length ? filteredWords : words
    const short = sourceWords.length > 1
      ? sourceWords.slice(0, 3).map((word) => word[0]).join('').toUpperCase()
      : sourceWords[0].slice(0, 3).toUpperCase()

    return {
      short,
      long: normalized.toUpperCase()
    }
  }

  /** @param {number} outs */
  function getOutsLabel(outs) {
    return `${outs} OUT${outs === 1 ? '' : 'S'}`
  }

  onDestroy(() => {
    clearTimeout(nameDebounceTimer)
    clearTimeout(flashTimer)
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
          <button class="btn-undo" on:click={undo} disabled={!previousMatch} title="Undo last action">
            ↩ Undo
          </button>
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
        <div class="match-layout">

          <div class="score-hero card">
            <div class="hero-toolbar">
              <span class="hero-preview-label">OBS Preview</span>
              <div class="hero-toolbar-actions">
                <button class="btn-icon" on:click={() => adjustInning(-1)} disabled={match.inning <= 1}>▼</button>
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
                <button class="btn-icon" on:click={() => adjustInning(1)}>▲</button>
              </div>
            </div>

            <div class="hero-scorebug">
              <div class="league-box">MLB</div>
              <div class="team-box">
                <span class="team-short">{getTeamParts(match.away_team_name).short}</span>
                <span class="team-long">{getTeamParts(match.away_team_name).long}</span>
              </div>
              <div class="score-box {flash.away_score ? 'flash' : ''}">{match.away_score}</div>
              <div class="score-separator"></div>
              <div class="team-box">
                <span class="team-short">{getTeamParts(match.home_team_name).short}</span>
                <span class="team-long">{getTeamParts(match.home_team_name).long}</span>
              </div>
              <div class="score-box {flash.home_score ? 'flash' : ''}">{match.home_score}</div>
              <div class="inning-box">
                <span class="half-arrow">{match.inning_half === 'top' ? '▲' : '▼'}</span>
                <span class="inning-text {flash.inning || flash.inning_half ? 'flash' : ''}">{getOrdinal(match.inning)}</span>
              </div>
              <div class="count-box">
                <div class="count-main">
                  <span class="balls-text">{match.balls}</span>
                  <span class="count-divider">-</span>
                  <span class="strikes-text">{match.strikes}</span>
                </div>
                <span class="count-caption">B - S</span>
              </div>
              <div class="outs-box">
                <div class="outs-pips hero-outs-pips">
                  {#each Array(3) as _, i}
                    <span class="out-pip {i < match.outs ? 'filled' : ''}"></span>
                  {/each}
                </div>
                <span class="outs-caption">{getOutsLabel(match.outs)}</span>
              </div>
              <div class="diamond-box">
                <svg class="bases-svg" viewBox="-6 -6 112 112" role="img" aria-label="Baseball diamond">
                  <polygon points="50,2 98,50 50,98 2,50" fill="rgba(255,255,255,0.03)" stroke="rgba(255,255,255,0.1)" stroke-width="1.25"/>
                  <polygon points="50,-4 60,6 50,16 40,6" fill={match.base2 ? '#ffc800' : 'rgba(255,255,255,0.1)'} stroke={match.base2 ? '#ffe37a' : 'rgba(255,255,255,0.1)'} stroke-width="1.8"/>
                  <polygon points="84,50 94,40 104,50 94,60" fill={match.base1 ? '#ffc800' : 'rgba(255,255,255,0.1)'} stroke={match.base1 ? '#ffe37a' : 'rgba(255,255,255,0.1)'} stroke-width="1.8"/>
                  <polygon points="-4,50 6,40 16,50 6,60" fill={match.base3 ? '#ffc800' : 'rgba(255,255,255,0.1)'} stroke={match.base3 ? '#ffe37a' : 'rgba(255,255,255,0.1)'} stroke-width="1.8"/>
                  <circle cx="50" cy="50" r="4" fill="rgba(255,255,255,0.2)" />
                </svg>
              </div>
            </div>

            {#if match.at_bat_text}
              <div class="hero-at-bat-strip">
                <span class="at-bat-label">NOW BATTING</span>
                <span class="at-bat-name">{match.at_bat_text}</span>
              </div>
            {/if}
          </div>

          <!-- Dos secciones claras: Visitante (Izquierda) y Local (Derecha) -->
          <div class="teams-split">
            <section class="card team-panel away-panel" style="--team-color: {match.away_team_color}">
              <h2>Visitante</h2>
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
                  placeholder="NYY Yankees"
                />
              </div>
              <p class="team-input-note">Usa “siglas + nombre” para separar ambas líneas en el overlay.</p>
              <div class="score-control">
                <button class="score-btn minus" on:click={() => adjustScore('away', -1)} disabled={match.away_score <= 0}>−</button>
                <span class="score-display {flash.away_score ? 'flash' : ''}">{match.away_score}</span>
                <button class="score-btn plus" on:click={() => adjustScore('away', 1)}>+</button>
              </div>
            </section>

            <section class="card team-panel home-panel" style="--team-color: {match.home_team_color}">
              <h2>Local</h2>
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
                  placeholder="BOS Red Sox"
                />
              </div>
              <p class="team-input-note">Ejemplo: “BOS Red Sox” mostrará siglas arriba y nombre abajo.</p>
              <div class="score-control">
                <button class="score-btn minus" on:click={() => adjustScore('home', -1)} disabled={match.home_score <= 0}>−</button>
                <span class="score-display {flash.home_score ? 'flash' : ''}">{match.home_score}</span>
                <button class="score-btn plus" on:click={() => adjustScore('home', 1)}>+</button>
              </div>
            </section>
          </div>

          <!-- Panel secundario: Conteo del Bateador (Bolas, Strikes, Outs) -->
          <section class="card count-panel">
            <h2>Conteo del Bateador</h2>
            <div class="count-grid">
              <div class="count-item">
                <span class="count-label">Bolas</span>
                <button class="count-btn balls" on:click={addBall}>
                  <div class="pip-row">
                    {#each Array(4) as _, i}
                      <span class="pip {i < match.balls ? 'on' : 'off'}"></span>
                    {/each}
                  </div>
                  <span class="count-number {flash.balls ? 'flash' : ''}">{match.balls}</span>
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
                  <span class="count-number {flash.strikes ? 'flash' : ''}">{match.strikes}</span>
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
                  <span class="count-number {flash.outs ? 'flash' : ''}">{match.outs}</span>
                </button>
              </div>
            </div>
            <button class="btn-clear" on:click={clearCount}>Clear Count</button>
          </section>

          <section class="card bases-panel">
            <h2>Corredores en base</h2>
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
          </section>

          <section class="card obs-settings-card">
            <h2>OBS View Options</h2>
            <div class="obs-toggles">
              <label class="obs-toggle">
                <input
                  type="checkbox"
                  checked={match.obs_show_count}
                  on:change={(e) => updateMatch({ obs_show_count: e.target.checked })}
                />
                <span class="toggle-label">Show innings, outs, strikes &amp; balls</span>
              </label>
              <label class="obs-toggle">
                <input
                  type="checkbox"
                  checked={match.obs_show_diamond}
                  on:change={(e) => updateMatch({ obs_show_diamond: e.target.checked })}
                />
                <span class="toggle-label">Show diamond (base runners)</span>
              </label>
            </div>
            <div class="banner-url-row">
              <label class="banner-url-label" for="banner-url-input">Advertising banners (450×100) — one image URL per line</label>
              <div class="banner-url-input-row">
                <textarea
                  id="banner-url-input"
                  value={match.banner_url || ''}
                  placeholder="https://example.com/banner-1.png&#10;&#10;https://example.com/banner-2.png"
                  class="banner-url-input"
                  on:change={(e) => {
                    const val = (e.target.value || '').replace(/\r\n/g, '\n')
                    if (!isValidBannerConfig(val)) {
                      error = 'Each banner URL must start with https://'
                      return
                    }
                    updateMatch({ banner_url: val.trim() ? val : null })
                  }}
                ></textarea>
                {#if match.banner_url}
                  <button class="btn-clear-banner" on:click={() => updateMatch({ banner_url: null })} title="Remove banner">✕</button>
                {/if}
              </div>
              <p class="obs-note banner-note">Banners rotate automatically in OBS. Leave blank lines to create intentional no-ad slots; even without blank lines, the rotation includes no-ad moments.</p>
            </div>
            <p class="obs-note">The score is always visible. Changes apply instantly to the OBS overlay.</p>
          </section>

          <section class="card at-bat-card">
            <h2>Turno al bat</h2>
            {#if loadingAtBatStats}
              <p class="obs-note">Cargando turnos al bat…</p>
            {:else if atBatStats.length > 0}
              <div class="batters-list">
                {#each atBatStats as batter}
                  <div class="batter-item">
                    <div class="batter-details">
                      <span class="batter-name">{batter.shortName}</span>
                      <span class="batter-stats">AB {batter.AB} · H {batter.H} · HR {batter.HR} · K {batter.K} · AVG {batter.AVG}</span>
                    </div>
                    <div class="batter-actions">
                      <button class="btn-at-bat-save" on:click={() => setAtBatBatter(batter.shortName)}>Mostrar</button>
                    </div>
                  </div>
                {/each}
              </div>
            {:else}
              <div class="at-bat-row">
                <input
                  type="text"
                  value={newBatterName}
                  placeholder="Agregar bateador"
                  class="at-bat-input"
                  maxlength="60"
                  on:input={(e) => { newBatterName = e.target.value }}
                />
                <button class="btn-at-bat-save" on:click={addBatterToList} disabled={!newBatterName.trim()}>Agregar</button>
              </div>
            {/if}
            {#if !loadingAtBatStats && !atBatStats.length && battersList.length > 0}
              <div class="batters-list">
                {#each battersList as batter, i}
                  <div class="batter-item">
                    <span class="batter-name">{batter}</span>
                    <div class="batter-actions">
                      <button class="btn-at-bat-save" on:click={() => setAtBatBatter(batter)}>Mostrar</button>
                      <button class="btn-clear-banner" on:click={() => removeBatterFromList(i)} title="Eliminar bateador">✕</button>
                    </div>
                  </div>
                {/each}
              </div>
            {:else if !loadingAtBatStats && !atBatStats.length}
              <p class="obs-note">Agrega bateadores para mostrarlos con un clic.</p>
            {/if}
            {#if atBatStatsError}
              <p class="obs-note">{atBatStatsError}</p>
            {/if}
            <div class="at-bat-current">
              <span class="at-bat-current-text">{match.at_bat_text ? `Mostrando: ${match.at_bat_text}` : 'No hay turno al bat activo'}</span>
              <button class="btn-clear-banner" on:click={clearAtBatText} disabled={!match.at_bat_text}>Limpiar turno</button>
            </div>
            <button class="btn-home-run" on:click={triggerHomeRun}>💥 Home Run</button>
          </section>

        </div>

        <!-- Fixed quick-action bar: large thumb-friendly buttons pinned to the bottom -->
        <div class="quick-action-bar">
          <button class="action-btn balls" on:click={addBall} aria-label="+1 Bola">
            <span class="action-label">+1 Bola</span>
            <span class="action-count">{match.balls} / 4</span>
          </button>
          <button class="action-btn strikes" on:click={addStrike} aria-label="+1 Strike">
            <span class="action-label">+1 Strike</span>
            <span class="action-count">{match.strikes} / 3</span>
          </button>
          <button class="action-btn outs" on:click={addOut} aria-label="+1 Out">
            <span class="action-label">+1 Out</span>
            <span class="action-count">{match.outs} / 3</span>
          </button>
          <div class="action-sep" role="separator"></div>
          <button
            class="action-btn score-team"
            on:click={() => adjustScore('away', 1)}
            style="--team-color: {match.away_team_color}"
            aria-label="+1 Carrera {match.away_team_name}"
          >
            <span class="action-label">+1 Carrera</span>
            <span class="action-team">{match.away_team_name}</span>
          </button>
          <button
            class="action-btn score-team"
            on:click={() => adjustScore('home', 1)}
            style="--team-color: {match.home_team_color}"
            aria-label="+1 Carrera {match.home_team_name}"
          >
            <span class="action-label">+1 Carrera</span>
            <span class="action-team">{match.home_team_name}</span>
          </button>
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
  /* ── Z-index scale ────────────────────────────────────────────────── */
  /* --z-fixed-bar: 200  — always on top of scrollable content          */

  /* ── Layout tokens ───────────────────────────────────────────────── */
  /* --quick-action-bar-height: 112px  (button 88px + padding 24px)    */
  /* Responsive overrides are applied inside the media queries below.   */
  .dashboard {
    --quick-action-bar-height: 112px;
    min-height: 100vh;
    display: flex;
    flex-direction: column;
    background: #000000;
  }

  header {
    background: #111111;
    border-bottom: 1px solid rgba(255,255,255,0.15);
    padding: 0.75rem 1rem;
    display: flex;
    align-items: center;
    justify-content: space-between;
    flex-shrink: 0;
    gap: 0.5rem;
  }

  .header-left {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    flex-shrink: 0;
  }

  .logo {
    font-size: 1.5rem;
  }

  h1 {
    font-size: 1.25rem;
    font-weight: 800;
    color: #ffffff;
  }

  .header-right {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    flex-shrink: 0;
    overflow: hidden;
  }

  .user-email {
    color: #aaaaaa;
    font-size: 0.85rem;
    max-width: 80px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .btn-logout {
    background: rgba(229, 57, 53, 0.15);
    border: 1px solid rgba(229, 57, 53, 0.3);
    color: #ff6b6b;
    border-radius: 6px;
    padding: 0.4rem 0.75rem;
    font-size: 0.8rem;
    font-weight: 600;
    min-height: 44px;
    transition: background 0.2s;
    white-space: nowrap;
    flex-shrink: 0;
  }

  .btn-logout:hover {
    background: rgba(229, 57, 53, 0.25);
  }

  main {
    flex: 1;
    padding: 1.5rem;
    padding-bottom: calc(1.5rem + var(--quick-action-bar-height) + env(safe-area-inset-bottom, 0px));
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
    background: #111111;
    border: 1px solid rgba(255,255,255,0.15);
    border-radius: 8px;
    padding: 0.5rem 0.875rem;
    flex: 1;
    min-width: 0;
    flex-wrap: wrap;
  }

  .obs-label {
    color: #aaaaaa;
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

  /* ── Match layout container ─────────────────────────────── */
  .match-layout {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  /* ── Score Hero: MLB-style preview ────────────────────────── */
  .score-hero {
    display: flex;
    flex-direction: column;
    gap: 1rem;
    padding: 1.5rem;
    background:
      linear-gradient(180deg, rgba(7, 16, 33, 0.98), rgba(5, 11, 24, 0.98));
    border-color: rgba(255,255,255,0.18);
  }

  .hero-toolbar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.75rem;
    flex-wrap: wrap;
  }

  .hero-preview-label {
    color: #8b8fa8;
    font-size: 0.72rem;
    font-weight: 800;
    letter-spacing: 0.12em;
    text-transform: uppercase;
  }

  .hero-toolbar-actions {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .hero-scorebug {
    display: inline-flex;
    align-items: stretch;
    align-self: flex-start;
    min-height: 50px;
    background: linear-gradient(180deg, #111925 0%, #060c14 100%);
    border: 1px solid rgba(255,255,255,0.18);
    border-radius: 6px;
    overflow: hidden;
    box-shadow:
      0 12px 26px rgba(0,0,0,0.45),
      inset 0 1px 0 rgba(255,255,255,0.08);
  }

  .league-box,
  .team-box,
  .score-box,
  .inning-box,
  .count-box,
  .outs-box,
  .diamond-box {
    display: flex;
    align-items: center;
    min-height: 50px;
  }

  .league-box {
    justify-content: center;
    margin: 10px 10px 10px 12px;
    min-width: 52px;
    min-height: 28px;
    height: 28px;
    padding: 0 10px;
    border-radius: 4px;
    background: linear-gradient(180deg, #ee2b2f 0%, #c70d18 100%);
    color: #ffffff;
    font-size: 0.95rem;
    font-weight: 900;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    box-shadow: inset 0 1px 0 rgba(255,255,255,0.22);
  }

  .team-box {
    flex-direction: column;
    justify-content: center;
    align-items: flex-start;
    gap: 1px;
    min-width: 96px;
    padding: 0 14px;
    background: linear-gradient(180deg, #162338 0%, #0e192a 100%);
    border-left: 1px solid rgba(255,255,255,0.04);
    border-right: 1px solid rgba(0,0,0,0.65);
  }

  .team-short {
    color: #ffffff;
    font-size: 1.05rem;
    font-weight: 900;
    letter-spacing: 0.02em;
    line-height: 1;
    text-transform: uppercase;
  }

  .team-long {
    color: #d7dbe3;
    font-size: 0.54rem;
    font-weight: 800;
    letter-spacing: 0.04em;
    line-height: 1.1;
    text-transform: uppercase;
    white-space: nowrap;
  }

  .score-box {
    justify-content: center;
    min-width: 44px;
    padding: 0 10px;
    background: linear-gradient(180deg, #111925 0%, #0a1019 100%);
    color: #ffffff;
    font-size: 1.85rem;
    font-weight: 900;
    font-variant-numeric: tabular-nums;
    text-shadow: 0 1px 0 rgba(0,0,0,0.45);
  }

  .score-separator {
    width: 6px;
    background: linear-gradient(180deg, #ff1f5d 0%, #c4063b 100%);
    box-shadow: inset 1px 0 0 rgba(255,255,255,0.18), inset -1px 0 0 rgba(0,0,0,0.35);
  }

  .inning-box {
    justify-content: center;
    gap: 4px;
    min-width: 68px;
    padding: 0 12px;
    background: linear-gradient(180deg, #121923 0%, #0a1019 100%);
    border-left: 1px solid rgba(255,255,255,0.04);
  }

  .half-arrow {
    color: #ffd22e;
    font-size: 0.9rem;
    line-height: 1;
    margin-top: -1px;
  }

  .inning-text {
    color: #ffffff;
    font-size: 1rem;
    font-weight: 900;
    letter-spacing: 0.01em;
    line-height: 1;
  }

  .count-box,
  .outs-box {
    flex-direction: column;
    justify-content: center;
    gap: 2px;
    min-width: 62px;
    padding: 0 10px;
    background: linear-gradient(180deg, #121923 0%, #0a1019 100%);
    border-left: 1px solid rgba(255,255,255,0.04);
  }

  .count-main {
    display: flex;
    align-items: baseline;
    gap: 2px;
  }

  .balls-text,
  .strikes-text,
  .count-divider {
    font-size: 0.98rem;
    font-weight: 900;
    line-height: 1;
  }

  .balls-text {
    color: #57ff2a;
  }

  .count-divider,
  .strikes-text {
    color: #ffd22e;
  }

  .count-caption,
  .outs-caption {
    color: #cfd6df;
    font-size: 0.44rem;
    font-weight: 800;
    letter-spacing: 0.08em;
    line-height: 1;
    text-transform: uppercase;
  }

  .outs-pips {
    display: flex;
    gap: 4px;
  }

  .out-pip {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    border: 1px solid rgba(255, 94, 84, 0.42);
    background: rgba(255, 168, 85, 0.18);
  }

  .out-pip.filled {
    background: #ff453a;
    border-color: #ff453a;
  }

  .hero-outs-pips {
    margin: 0.1rem 0;
  }

  .diamond-box {
    justify-content: center;
    min-width: 54px;
    padding: 0 10px;
    background: linear-gradient(180deg, #121923 0%, #0a1019 100%);
    border-left: 1px solid rgba(255,255,255,0.04);
  }

  .bases-svg {
    width: 34px;
    height: 34px;
    overflow: visible;
  }

  .hero-at-bat-strip {
    display: inline-flex;
    align-items: center;
    gap: 0;
    align-self: flex-end;
    margin-top: -3px;
    margin-right: 2px;
    min-height: 29px;
    max-width: calc(100% - 216px);
    border-radius: 0 0 6px 6px;
    border: 1px solid rgba(255,255,255,0.14);
    background: linear-gradient(180deg, #152033 0%, #0a1019 100%);
    box-shadow: 0 10px 24px rgba(0, 0, 0, 0.38);
  }

  .at-bat-label {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    align-self: stretch;
    padding: 0 11px;
    background: linear-gradient(180deg, #ffd91a 0%, #f1c400 100%);
    color: #05080d;
    font-size: 0.72rem;
    font-weight: 900;
    letter-spacing: 0.05em;
    text-transform: uppercase;
  }

  .at-bat-name {
    color: #ffffff;
    font-size: 0.54rem;
    font-weight: 900;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    padding: 0 12px;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  /* ── Teams Split: Visitante (Left) | Local (Right) ────────── */
  .teams-split {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 1rem;
  }

  .team-panel {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .away-panel {
    border-top: 4px solid var(--team-color, rgba(255,255,255,0.1));
  }

  .home-panel {
    border-top: 4px solid var(--team-color, rgba(255,255,255,0.1));
  }

  @media (max-width: 768px) {
    .teams-split {
      grid-template-columns: 1fr;
    }

    .score-hero {
      padding: 1.5rem;
    }

    .hero-scorebug,
    .hero-at-bat-strip {
      transform-origin: top left;
      transform: scale(0.9);
    }
  }

  /* ── Small iPhones (SE, 12/13 mini) ──────────────────────── */
  @media (max-width: 375px) {
    .hero-scorebug,
    .hero-at-bat-strip {
      transform: scale(0.78);
    }

    .score-display {
      font-size: 2rem;
    }

    .score-btn {
      width: 48px;
      height: 48px;
      font-size: 1.3rem;
    }

    .btn-icon {
      width: 40px;
      height: 40px;
    }

    .base-btn-ui {
      width: 48px;
      height: 48px;
      font-size: 0.75rem;
    }

    .bases-gap {
      width: 48px;
    }

    main {
      padding: 1rem;
      padding-bottom: calc(1rem + var(--quick-action-bar-height) + env(safe-area-inset-bottom, 0px));
    }

    .card {
      padding: 1rem;
    }

    .quick-action-bar {
      gap: 8px;
      padding: 8px 12px;
      padding-bottom: max(8px, env(safe-area-inset-bottom, 8px));
    }

    .action-btn {
      min-height: 72px;
      border-radius: 10px;
    }

    .action-label {
      font-size: 0.8rem;
    }

    .action-count,
    .action-team {
      font-size: 0.65rem;
    }
  }

  /* ── Landscape orientation handling ──────────────────────── */
  @media (max-height: 500px) and (orientation: landscape) {
    .score-hero {
      padding: 0.75rem 1rem;
      gap: 1rem;
    }

    .hero-scorebug,
    .hero-at-bat-strip {
      transform-origin: top left;
      transform: scale(0.86);
    }

    main {
      padding: 0.75rem;
      padding-bottom: calc(0.75rem + var(--quick-action-bar-height) + env(safe-area-inset-bottom, 0px));
    }

    .card {
      padding: 0.75rem;
    }

    .card h2 {
      font-size: 0.7rem;
      margin-bottom: 0.75rem;
    }

    .count-btn {
      min-height: 72px;
      padding: 0.5rem;
    }

    .count-number {
      font-size: 1.4rem;
    }

    .score-control {
      gap: 0.3rem;
    }

    .count-label {
      font-size: 0.6rem;
    }
  }

  /* ── iPad landscape / large phones landscape ─────────────── */
  @media (min-width: 769px) and (max-height: 600px) and (orientation: landscape) {
    main {
      padding: 1rem;
      padding-bottom: calc(1rem + var(--quick-action-bar-height) + env(safe-area-inset-bottom, 0px));
    }

    .score-hero {
      padding: 1rem 1.5rem;
    }

    .hero-scorebug,
    .hero-at-bat-strip {
      transform-origin: top left;
      transform: scale(0.92);
    }

    .count-btn {
      min-height: 72px;
    }

    .card {
      padding: 1rem;
    }
  }

  /* ── Count Panel: Conteo del Bateador ─────────────────────── */
  .count-panel {
    background: #161b27;
    border-color: rgba(255,255,255,0.12);
  }

  .card {
    background: #111111;
    border: 1px solid rgba(255,255,255,0.15);
    border-radius: 12px;
    padding: 1.5rem;
  }

  .card h2 {
    font-size: 0.8rem;
    font-weight: 800;
    text-transform: uppercase;
    letter-spacing: 0.1em;
    color: #aaaaaa;
    margin-bottom: 1.25rem;
  }

  .team-inputs {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .color-picker {
    width: 44px;
    height: 44px;
    border: none;
    border-radius: 8px;
    cursor: pointer;
    padding: 2px;
    background: rgba(255,255,255,0.1);
    flex-shrink: 0;
  }

  .team-name-input {
    background: rgba(255,255,255,0.07);
    border: 1px solid rgba(255,255,255,0.2);
    border-radius: 6px;
    padding: 0.4rem 0.6rem;
    color: var(--team-color, #ffffff);
    font-size: 0.95rem;
    font-weight: 800;
    text-transform: uppercase;
    width: 100%;
    outline: none;
    transition: border-color 0.2s;
  }

  .team-name-input:focus {
    border-color: rgba(255,255,255,0.5);
  }

  .team-input-note {
    color: #8b8fa8;
    font-size: 0.76rem;
    line-height: 1.4;
  }

  .score-control {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .score-btn {
    width: 56px;
    height: 56px;
    border-radius: 8px;
    border: 1px solid rgba(255,255,255,0.15);
    background: rgba(255,255,255,0.05);
    color: #fff;
    font-size: 1.6rem;
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
    color: #FFE600;
    min-width: 3rem;
    text-align: center;
    font-variant-numeric: tabular-nums;
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

  .bases-buttons {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.5rem;
    margin-bottom: 0;
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
    color: #000000;
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
    color: #000000;
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
    color: #000000;
  }
  .base-btn-ui.base3.occupied:hover {
    background: #3b9de0;
    border-color: #3b9de0;
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
    font-weight: 800;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: #aaaaaa;
  }

  .count-btn {
    background: rgba(255,255,255,0.05);
    border: 1px solid rgba(255,255,255,0.15);
    border-radius: 10px;
    padding: 1rem 0.5rem;
    width: 100%;
    min-height: 100px;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 0.6rem;
    transition: background 0.15s, border-color 0.15s;
  }

  .count-btn:hover {
    background: rgba(255,255,255,0.1);
    border-color: rgba(255,255,255,0.3);
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
    color: #FFE600;
    line-height: 1;
    font-variant-numeric: tabular-nums;
  }

  @media (min-width: 769px) and (max-width: 1024px) {
    .score-btn,
    .btn-icon,
    .count-btn {
      min-height: 64px;
    }

    .score-btn {
      width: 64px;
      height: 64px;
    }

    .btn-icon {
      width: 64px;
      height: 64px;
    }

    .base-btn-ui {
      width: 64px;
      height: 64px;
      font-size: 0.95rem;
    }

    .bases-gap {
      width: 64px;
    }

    .hero-scorebug,
    .hero-at-bat-strip {
      transform-origin: top left;
      transform: scale(0.92);
    }

    .score-display {
      font-size: 3rem;
    }
  }

  .btn-clear {
    width: 100%;
    background: rgba(255,255,255,0.06);
    border: 1px solid rgba(255,255,255,0.15);
    color: #aaaaaa;
    border-radius: 8px;
    padding: 0.6rem;
    font-size: 0.85rem;
    font-weight: 700;
    min-height: 44px;
    transition: background 0.15s, color 0.15s;
  }

  .btn-clear:hover {
    background: rgba(255,255,255,0.12);
    color: #ffffff;
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
    color: #aaaaaa;
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

  .obs-toggles {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    margin-bottom: 0.75rem;
  }

  .obs-toggle {
    display: flex;
    align-items: center;
    gap: 0.6rem;
    cursor: pointer;
    user-select: none;
  }

  .obs-toggle input[type="checkbox"] {
    width: 18px;
    height: 18px;
    accent-color: #1a73e8;
    cursor: pointer;
    flex-shrink: 0;
  }

  .toggle-label {
    font-size: 0.9rem;
    color: #ffffff;
    font-weight: 500;
  }

  .obs-note {
    font-size: 0.78rem;
    color: #aaaaaa;
    margin-top: 0.25rem;
  }

  .banner-url-row {
    margin-top: 1rem;
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
  }

  .banner-url-label {
    font-size: 0.78rem;
    font-weight: 700;
    color: #aaaaaa;
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }

  .banner-url-input-row {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .banner-url-input {
    flex: 1;
    background: #1a1a2e;
    border: 1px solid rgba(255,255,255,0.2);
    border-radius: 6px;
    color: #ffffff;
    font-size: 0.85rem;
    padding: 0.45rem 0.75rem;
    min-height: 100px;
    resize: vertical;
    font-family: inherit;
  }

  .banner-url-input:focus {
    outline: none;
    border-color: rgba(26, 115, 232, 0.6);
  }

  .btn-clear-banner {
    background: rgba(229, 57, 53, 0.12);
    border: 1px solid rgba(229, 57, 53, 0.3);
    color: #ff6b6b;
    border-radius: 6px;
    padding: 0.3rem 0.6rem;
    font-size: 0.8rem;
    min-height: 36px;
    transition: background 0.2s;
    white-space: nowrap;
  }

  .btn-clear-banner:hover {
    background: rgba(229, 57, 53, 0.25);
  }

  .at-bat-card {
    display: flex;
    flex-direction: column;
    gap: 0.8rem;
  }

  .at-bat-row {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    flex-wrap: wrap;
  }

  .at-bat-current {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.5rem;
    flex-wrap: wrap;
  }

  .at-bat-current-text {
    color: #ffffff;
    font-size: 0.85rem;
    font-weight: 600;
  }

  .at-bat-input {
    flex: 1;
    min-width: 220px;
    background: #1a1a2e;
    border: 1px solid rgba(255,255,255,0.2);
    border-radius: 6px;
    color: #ffffff;
    font-size: 0.9rem;
    padding: 0.5rem 0.75rem;
    min-height: 40px;
  }

  .at-bat-input:focus {
    outline: none;
    border-color: rgba(26, 115, 232, 0.6);
  }

  .btn-at-bat-save {
    background: rgba(26, 115, 232, 0.2);
    border: 1px solid rgba(26, 115, 232, 0.45);
    color: #63b3ed;
    border-radius: 6px;
    padding: 0.45rem 0.9rem;
    min-height: 40px;
    font-size: 0.85rem;
    font-weight: 700;
  }

  .btn-at-bat-save:hover {
    background: rgba(26, 115, 232, 0.3);
  }

  .batters-list {
    display: flex;
    flex-direction: column;
    gap: 0.45rem;
    max-height: 240px;
    overflow-y: auto;
    padding-right: 0.2rem;
  }

  .batter-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.5rem;
    padding: 0.45rem 0.55rem;
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 8px;
    background: rgba(255,255,255,0.03);
  }

  .batter-name {
    color: #ffffff;
    font-size: 0.9rem;
    font-weight: 600;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .batter-details {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }

  .batter-stats {
    color: #b6c6d8;
    font-size: 0.73rem;
    font-weight: 700;
    letter-spacing: 0.01em;
    line-height: 1.2;
  }

  .batter-actions {
    display: flex;
    align-items: center;
    gap: 0.35rem;
    flex-shrink: 0;
  }

  .btn-home-run {
    width: 100%;
    min-height: 44px;
    border-radius: 8px;
    border: 1px solid rgba(248, 113, 113, 0.45);
    background: rgba(248, 113, 113, 0.14);
    color: #fca5a5;
    font-size: 0.9rem;
    font-weight: 800;
    text-transform: uppercase;
    letter-spacing: 0.06em;
  }

  .btn-home-run:hover {
    background: rgba(248, 113, 113, 0.25);
  }

  .banner-note {
    margin-top: 0;
  }

  .btn-undo {
    background: rgba(251, 191, 36, 0.12);
    border: 1px solid rgba(251, 191, 36, 0.35);
    color: #fbbf24;
    border-radius: 8px;
    padding: 0.625rem 1.25rem;
    font-size: 0.95rem;
    font-weight: 600;
    min-height: 44px;
    transition: background 0.2s, opacity 0.2s;
    white-space: nowrap;
  }

  .btn-undo:hover:not(:disabled) {
    background: rgba(251, 191, 36, 0.25);
  }

  .btn-undo:disabled {
    opacity: 0.35;
    cursor: default;
  }

  @keyframes flash-update {
    0%   { text-shadow: 0 0 10px rgba(255, 255, 255, 0.95), 0 0 24px rgba(255, 255, 255, 0.5); }
    100% { text-shadow: none; }
  }

  .flash {
    animation: flash-update 0.2s ease-out;
  }

  /* ── Quick-action bar ─────────────────────────────────────────────── */
  .quick-action-bar {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    display: flex;
    gap: 12px;
    padding: 12px 16px;
    padding-bottom: max(12px, env(safe-area-inset-bottom, 12px));
    background: rgba(15, 17, 23, 0.97);
    backdrop-filter: blur(16px);
    -webkit-backdrop-filter: blur(16px);
    border-top: 1px solid rgba(255,255,255,0.1);
    z-index: 200; /* --z-fixed-bar */
  }

  .action-btn {
    flex: 1;
    min-height: 88px;
    border-radius: 14px;
    border: 2px solid rgba(255,255,255,0.12);
    background: rgba(255,255,255,0.06);
    color: #fff;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 5px;
    cursor: pointer;
    transition: background 0.15s, transform 0.1s;
    touch-action: manipulation;
    -webkit-tap-highlight-color: transparent;
    padding: 0.5rem;
  }

  .action-btn:hover {
    background: rgba(255,255,255,0.1);
  }

  .action-btn:active {
    transform: scale(0.96);
  }

  /* Ball button */
  .action-btn.balls {
    border-color: rgba(74, 222, 128, 0.45);
    background: rgba(74, 222, 128, 0.08);
  }
  .action-btn.balls:hover {
    background: rgba(74, 222, 128, 0.15);
  }
  .action-btn.balls .action-label { color: #4ade80; }

  /* Strike button */
  .action-btn.strikes {
    border-color: rgba(251, 191, 36, 0.45);
    background: rgba(251, 191, 36, 0.08);
  }
  .action-btn.strikes:hover {
    background: rgba(251, 191, 36, 0.15);
  }
  .action-btn.strikes .action-label { color: #fbbf24; }

  /* Out button */
  .action-btn.outs {
    border-color: rgba(248, 113, 113, 0.45);
    background: rgba(248, 113, 113, 0.08);
  }
  .action-btn.outs:hover {
    background: rgba(248, 113, 113, 0.15);
  }
  .action-btn.outs .action-label { color: #f87171; }

  /* Score (team) buttons — color driven by CSS variable set inline */
  .action-btn.score-team {
    border-color: rgba(255,255,255,0.18);
    background: rgba(255,255,255,0.06);
  }
  .action-btn.score-team:hover {
    background: rgba(255,255,255,0.11);
  }
  .action-btn.score-team .action-label {
    color: var(--team-color, #fff);
  }

  .action-label {
    font-size: 0.88rem;
    font-weight: 800;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    line-height: 1;
  }

  .action-count {
    font-size: 0.72rem;
    color: rgba(255,255,255,0.5);
    font-variant-numeric: tabular-nums;
  }

  .action-team {
    font-size: 0.72rem;
    color: rgba(255,255,255,0.6);
    text-transform: uppercase;
    font-weight: 700;
    max-width: 100%;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .action-sep {
    width: 1px;
    background: rgba(255,255,255,0.12);
    align-self: stretch;
    margin: 8px 0;
    flex-shrink: 0;
  }

  /* Larger targets on tablets (iPad landscape / portrait) */
  @media (min-width: 769px) {
    .dashboard { --quick-action-bar-height: 128px; } /* button 100px + padding 28px */
    .quick-action-bar {
      gap: 16px;
      padding: 14px 24px;
      padding-bottom: max(14px, env(safe-area-inset-bottom, 14px));
    }
    .action-btn {
      min-height: 100px;
    }
    .action-label {
      font-size: 1rem;
    }
    .action-count,
    .action-team {
      font-size: 0.8rem;
    }
  }

  /* Extra large on big-screen landscape (1025px+) */
  @media (min-width: 1025px) {
    .dashboard { --quick-action-bar-height: 142px; } /* button 110px + padding 32px */
    .quick-action-bar {
      padding: 16px 32px;
      padding-bottom: max(16px, env(safe-area-inset-bottom, 16px));
      gap: 20px;
    }
    .action-btn {
      min-height: 110px;
      border-radius: 16px;
    }
    .action-label {
      font-size: 1.05rem;
    }
  }
</style>
