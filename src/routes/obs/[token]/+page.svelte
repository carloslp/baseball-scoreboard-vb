<svelte:options runes={false} />

<script>
  import { onMount, onDestroy } from 'svelte'
  import { page } from '$app/stores'
  import { supabase } from '$lib/supabase'

  let token = ''
  let match = null
  let loading = true
  let channel = null
  let showAtBatBanner = false
  let atBatTimer = null
  let showHomeRunAnimation = false
  let homeRunTimer = null
  let bannerRotationTimer = null
  let bannerRotationSlots = []
  let currentBannerSlotIndex = 0
  let lastBannerConfig = ''

  $: token = $page.params.token || ''

  onMount(async () => {
    await loadMatch()
    subscribeToRealtime()
  })

  onDestroy(() => {
    clearTimeout(atBatTimer)
    clearTimeout(homeRunTimer)
    clearInterval(bannerRotationTimer)
    if (channel) {
      supabase.removeChannel(channel)
    }
  })

  async function loadMatch() {
    loading = true
    const { data, error } = await supabase
      .from('matches')
      .select('*')
      .eq('user_obs_token', token)
      .eq('is_active', true)
      .single()

    if (!error) {
      match = data
      syncBannerRotation()
    } else {
      match = null
      syncBannerRotation()
    }
    loading = false
  }

  function triggerAtBatBanner() {
    showAtBatBanner = true
    clearTimeout(atBatTimer)
    atBatTimer = setTimeout(() => {
      showAtBatBanner = false
    }, 5000)
  }

  function triggerHomeRunAnimation() {
    showHomeRunAnimation = true
    clearTimeout(homeRunTimer)
    homeRunTimer = setTimeout(() => {
      showHomeRunAnimation = false
    }, 3600)
  }

  function subscribeToRealtime() {
    channel = supabase
      .channel('obs-match-' + token)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'matches',
          filter: `user_obs_token=eq.${token}`
        },
        (payload) => {
          if (payload.eventType === 'UPDATE' || payload.eventType === 'INSERT') {
            if (payload.new.is_active) {
              const prevCounter = match?.home_run_counter || 0
              const prevAtBatCounter = match?.at_bat_counter || 0
              match = payload.new
              syncBannerRotation()
              if ((payload.new.at_bat_counter || 0) > prevAtBatCounter && payload.new.at_bat_text) {
                triggerAtBatBanner()
              }
              if ((payload.new.home_run_counter || 0) > prevCounter) {
                triggerHomeRunAnimation()
              }
            } else {
              match = null
              syncBannerRotation()
            }
          } else if (payload.eventType === 'DELETE') {
            match = null
            syncBannerRotation()
          }
        }
      )
      .subscribe()
  }

  function buildBannerRotationSlots(value) {
    if (typeof value !== 'string') return []

    const lines = value.replace(/\r\n/g, '\n').split('\n')
    const slots = []
    let hasValidBanner = false

    for (const line of lines) {
      const trimmed = line.trim()
      if (!trimmed) {
        slots.push(null)
      } else if (trimmed.startsWith('https://')) {
        slots.push(trimmed)
        hasValidBanner = true
      }
    }

    if (!hasValidBanner) return []
    if (!slots.includes(null)) slots.push(null)
    return slots
  }

  function syncBannerRotation() {
    const bannerConfig = typeof match?.banner_url === 'string' ? match.banner_url : ''
    if (bannerConfig === lastBannerConfig) return

    lastBannerConfig = bannerConfig
    bannerRotationSlots = buildBannerRotationSlots(bannerConfig)
    currentBannerSlotIndex = 0
    clearInterval(bannerRotationTimer)

    if (bannerRotationSlots.length > 1) {
      bannerRotationTimer = setInterval(() => {
        currentBannerSlotIndex = (currentBannerSlotIndex + 1) % bannerRotationSlots.length
      }, 8000)
    }
  }

  /** @param {number} number */
  function getOrdinal(number) {
    const lastTwoDigits = number % 100
    if (lastTwoDigits >= 11 && lastTwoDigits <= 13) return number + 'th'
    const lastDigit = number % 10
    return number + (['th','st','nd','rd'][lastDigit] || 'th')
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
</script>

<svelte:head>
  <style>
    html, body {
      background: transparent !important;
      margin: 0;
      padding: 0;
    }
  </style>
</svelte:head>

<div class="obs-container">
  {#if !loading && match}
    {#if showHomeRunAnimation}
      <div class="home-run-overlay" role="status" aria-live="polite">
        <div class="home-run-scene">
          <span class="home-run-text">HOME RUN!</span>
          <div class="home-run-swing">
            <span class="home-run-ball" aria-hidden="true"></span>
            <span class="home-run-bat" aria-hidden="true"></span>
            <span class="home-run-impact" aria-hidden="true"></span>
          </div>
        </div>
      </div>
    {/if}

    <div class="score-stack">
      <div class="score-bug">
        <div class="score-bug-header">
          <span class="league-pill">MLB</span>
        </div>

        <div class="teams-panel">
          <div class="team-row">
            <div class="team-accent" style="background: {match.away_team_color}"></div>
            <div class="team-copy">
              <span class="team-short">{getTeamParts(match.away_team_name).short}</span>
              <span class="team-long">{getTeamParts(match.away_team_name).long}</span>
            </div>
            <span class="team-score">{match.away_score}</span>
          </div>

          <div class="team-row">
            <div class="team-accent" style="background: {match.home_team_color}"></div>
            <div class="team-copy">
              <span class="team-short">{getTeamParts(match.home_team_name).short}</span>
              <span class="team-long">{getTeamParts(match.home_team_name).long}</span>
            </div>
            <span class="team-score">{match.home_score}</span>
          </div>
        </div>

        {#if match.obs_show_count !== false || match.obs_show_diamond !== false}
          <div class="status-row">
            {#if match.obs_show_count !== false}
              <div class="status-card">
                <span class="status-label">Inning</span>
                <div class="inning-display">
                  <span class="half-arrow">{match.inning_half === 'top' ? '▲' : '▼'}</span>
                  <span class="status-value">{getOrdinal(match.inning)}</span>
                </div>
              </div>

              <div class="status-card">
                <span class="status-label">Count</span>
                <span class="status-value">{match.balls} - {match.strikes}</span>
                <span class="status-subvalue">B - S</span>
              </div>

              <div class="status-card">
                <span class="status-label">Outs</span>
                <div class="outs-pips">
                  {#each Array(3) as _, i}
                    <span class="out-pip {i < match.outs ? 'filled' : ''}"></span>
                  {/each}
                </div>
                <span class="status-subvalue">{getOutsLabel(match.outs)}</span>
              </div>
            {/if}

            {#if match.obs_show_diamond !== false}
              <div class="status-card bases-card">
                <span class="status-label">Bases</span>
                <svg class="bases-svg" viewBox="-6 -6 112 112" role="img" aria-label="Baseball diamond">
                  <polygon points="50,2 98,50 50,98 2,50" fill="none" stroke="rgba(255,255,255,0.18)" stroke-width="1.5"/>
                  <polygon points="50,88 56,94 50,100 44,94" fill="rgba(255,255,255,0.25)"/>
                  <polygon points="50,-4 56,2 50,8 44,2"
                    fill={match.base2 ? '#ffd447' : 'rgba(255,255,255,0.08)'}
                    stroke={match.base2 ? '#ffd447' : 'rgba(255,255,255,0.35)'}
                    stroke-width="2"/>
                  <polygon points="88,50 98,42 106,50 98,58"
                    fill={match.base1 ? '#ffd447' : 'rgba(255,255,255,0.08)'}
                    stroke={match.base1 ? '#ffd447' : 'rgba(255,255,255,0.35)'}
                    stroke-width="2"/>
                  <polygon points="-6,50 2,42 10,50 2,58"
                    fill={match.base3 ? '#ffd447' : 'rgba(255,255,255,0.08)'}
                    stroke={match.base3 ? '#ffd447' : 'rgba(255,255,255,0.35)'}
                    stroke-width="2"/>
                </svg>
              </div>
            {/if}
          </div>
        {/if}
      </div>

      {#if match.at_bat_text}
        <div class="at-bat-strip {showAtBatBanner ? 'live' : ''}">
          <span class="at-bat-label">NOW BATTING</span>
          <span class="at-bat-name">{match.at_bat_text}</span>
        </div>
      {/if}

      <div class="banner-strip">
        <div class="banner-header">SPONSOR</div>
        {#if bannerRotationSlots[currentBannerSlotIndex]}
          <img
            src={bannerRotationSlots[currentBannerSlotIndex]}
            alt="Advertising banner"
            class="banner-inline-img"
            width="450"
            height="100"
          />
        {:else}
          <div class="banner-placeholder" aria-label="Sponsor placeholder">
            ADD SPONSOR
          </div>
        {/if}
      </div>
    </div>
  {/if}
</div>

<style>
  :global(html), :global(body) {
    background: transparent !important;
    margin: 0;
    padding: 0;
  }

  .obs-container {
    display: flex;
    align-items: flex-start;
    justify-content: flex-end;
    min-height: 100vh;
    padding: 20px;
    background: transparent;
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  }

  .score-stack {
    display: flex;
    flex-direction: column;
    align-items: stretch;
    gap: 8px;
    width: min(100%, 450px);
  }

  .score-bug {
    display: flex;
    flex-direction: column;
    background:
      linear-gradient(180deg, rgba(7, 16, 33, 0.98), rgba(5, 11, 24, 0.98));
    border: 1px solid rgba(255,255,255,0.24);
    border-radius: 14px;
    overflow: hidden;
    backdrop-filter: blur(12px);
    box-shadow: 0 14px 32px rgba(0,0,0,0.5);
  }

  .score-bug-header {
    display: flex;
    align-items: center;
    justify-content: flex-start;
    padding: 0.55rem 0.8rem 0.3rem;
  }

  .league-pill {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 3.1rem;
    padding: 0.22rem 0.6rem;
    border-radius: 999px;
    background: linear-gradient(90deg, #0a3c91, #0d57cb);
    color: #ffffff;
    font-size: 0.68rem;
    font-weight: 900;
    letter-spacing: 0.18em;
    text-transform: uppercase;
    box-shadow: inset 0 0 0 1px rgba(255,255,255,0.18);
  }

  .teams-panel {
    display: flex;
    flex-direction: column;
    padding: 0 0.45rem 0.45rem;
    gap: 0.35rem;
  }

  .team-row {
    display: grid;
    grid-template-columns: 5px minmax(0, 1fr) auto;
    align-items: center;
    gap: 0.7rem;
    min-height: 62px;
    padding: 0.55rem 0.8rem;
    border-radius: 10px;
    background: linear-gradient(135deg, rgba(255,255,255,0.08), rgba(255,255,255,0.03));
  }

  .team-accent {
    width: 5px;
    height: 100%;
    min-height: 44px;
    border-radius: 999px;
    box-shadow: 0 0 12px rgba(255,255,255,0.16);
  }

  .team-copy {
    min-width: 0;
    display: flex;
    flex-direction: column;
    gap: 0.12rem;
  }

  .team-short {
    color: #ffffff;
    font-size: 1.18rem;
    font-weight: 900;
    letter-spacing: 0.12em;
    line-height: 1;
    text-transform: uppercase;
  }

  .team-long {
    color: rgba(221,232,255,0.88);
    font-size: 0.7rem;
    font-weight: 800;
    letter-spacing: 0.12em;
    text-transform: uppercase;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .team-score {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-width: 58px;
    padding: 0.2rem 0.6rem;
    border-radius: 10px;
    background: rgba(0,0,0,0.38);
    color: #ffffff;
    font-size: 2rem;
    font-weight: 900;
    font-variant-numeric: tabular-nums;
    line-height: 1;
    box-shadow: inset 0 0 0 1px rgba(255,255,255,0.08);
  }

  .status-row {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(90px, 1fr));
    gap: 0.45rem;
    padding: 0 0.45rem 0.55rem;
  }

  .status-card {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 0.3rem;
    min-height: 80px;
    padding: 0.7rem 0.55rem;
    border-radius: 10px;
    background: rgba(255,255,255,0.05);
    box-shadow: inset 0 0 0 1px rgba(255,255,255,0.07);
    text-align: center;
  }

  .status-label,
  .banner-header,
  .at-bat-label {
    color: rgba(201,216,255,0.88);
    font-size: 0.58rem;
    font-weight: 900;
    letter-spacing: 0.16em;
    text-transform: uppercase;
  }

  .status-value {
    color: #ffffff;
    font-size: 1rem;
    font-weight: 900;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    font-variant-numeric: tabular-nums;
  }

  .status-subvalue {
    color: rgba(220,228,247,0.75);
    font-size: 0.68rem;
    font-weight: 800;
    letter-spacing: 0.14em;
    text-transform: uppercase;
  }

  .inning-display {
    display: flex;
    align-items: center;
    gap: 0.35rem;
  }

  .half-arrow {
    color: #ffd447;
    font-size: 0.8rem;
    line-height: 1;
  }

  .outs-pips {
    display: flex;
    gap: 5px;
  }

  .out-pip {
    width: 9px;
    height: 9px;
    border-radius: 50%;
    border: 1.5px solid rgba(248,113,113,0.42);
    background: transparent;
    transition: background 0.15s;
  }

  .out-pip.filled {
    background: #f87171;
    border-color: #f87171;
  }

  .bases-card {
    gap: 0.18rem;
  }

  .bases-svg {
    width: 48px;
    height: 48px;
    overflow: visible;
  }

  .at-bat-strip,
  .banner-strip {
    border-radius: 12px;
    border: 1px solid rgba(255,255,255,0.22);
    background: linear-gradient(180deg, rgba(7,16,33,0.96), rgba(5,11,24,0.96));
    box-shadow: 0 10px 24px rgba(0, 0, 0, 0.38);
  }

  .at-bat-strip {
    display: flex;
    align-items: center;
    justify-content: flex-start;
    gap: 0.65rem;
    padding: 0.7rem 0.85rem;
    animation: panel-enter 0.35s ease-out;
  }

  .at-bat-strip.live {
    box-shadow:
      0 10px 24px rgba(0, 0, 0, 0.38),
      0 0 0 1px rgba(255, 212, 71, 0.26);
  }

  .at-bat-name {
    color: #ffffff;
    font-size: 0.84rem;
    font-weight: 900;
    letter-spacing: 0.05em;
    text-transform: uppercase;
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .banner-strip {
    display: flex;
    flex-direction: column;
    gap: 0.45rem;
    padding: 0.65rem 0.85rem 0.85rem;
    animation: panel-enter 0.35s ease-out;
  }

  .banner-inline-img,
  .banner-placeholder {
    width: 100%;
    height: 100px;
    border-radius: 10px;
    overflow: hidden;
  }

  .banner-inline-img {
    object-fit: cover;
    display: block;
    border: 1px solid rgba(255,255,255,0.14);
  }

  .banner-placeholder {
    display: flex;
    align-items: center;
    justify-content: center;
    background:
      linear-gradient(135deg, rgba(255,255,255,0.08), rgba(255,255,255,0.03));
    color: rgba(221,232,255,0.56);
    font-size: 0.72rem;
    font-weight: 800;
    letter-spacing: 0.18em;
    text-transform: uppercase;
    border: 1px dashed rgba(255,255,255,0.14);
  }

  @keyframes panel-enter {
    from {
      opacity: 0;
      transform: translateY(-6px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  .home-run-overlay {
    position: fixed;
    inset: 0;
    pointer-events: none;
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 999;
  }

  .home-run-scene {
    position: relative;
    width: min(92vw, 980px);
    height: min(70vh, 560px);
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .home-run-text {
    font-size: clamp(2.2rem, 8vw, 6rem);
    font-weight: 900;
    letter-spacing: 0.12em;
    color: #ffe600;
    text-shadow:
      0 0 14px rgba(255, 230, 0, 0.85),
      0 0 28px rgba(255, 111, 97, 0.55),
      0 0 44px rgba(255, 56, 56, 0.5);
    animation: home-run-text-seq 1.2s ease-out forwards;
  }

  .home-run-swing {
    position: absolute;
    left: 50%;
    top: 58%;
    width: min(70vw, 760px);
    height: min(38vh, 320px);
    transform: translate(-50%, -50%);
  }

  .home-run-ball {
    position: absolute;
    left: 50%;
    top: 54%;
    width: 24px;
    height: 24px;
    border-radius: 50%;
    background: radial-gradient(circle at 35% 35%, #ffffff 0 42%, #e7e7e7 43% 100%);
    box-shadow: 0 0 16px rgba(255,255,255,0.7);
    transform: translate(-50%, -50%);
    animation: ball-launch 1.25s cubic-bezier(0.12, 0.73, 0.18, 1) 1.55s forwards;
  }

  .home-run-bat {
    position: absolute;
    left: calc(50% - 150px);
    top: calc(54% + 94px);
    width: 220px;
    height: 16px;
    border-radius: 12px;
    background: linear-gradient(90deg, #e5be82 0%, #d6a86f 65%, #9d6c39 100%);
    box-shadow: 0 0 12px rgba(0,0,0,0.45);
    transform-origin: 12% 50%;
    transform: rotate(55deg);
    animation: bat-swing 0.65s cubic-bezier(0.2, 0.9, 0.2, 1) 1.2s forwards;
  }

  .home-run-impact {
    position: absolute;
    left: 50%;
    top: 54%;
    width: 18px;
    height: 18px;
    border-radius: 50%;
    border: 2px solid rgba(255, 246, 153, 0.95);
    transform: translate(-50%, -50%) scale(0.1);
    opacity: 0;
    animation: bat-impact 0.35s ease-out 1.5s forwards;
  }

  @keyframes home-run-text-seq {
    0% {
      transform: scale(0.65);
      opacity: 0;
    }
    15% {
      transform: scale(1.1);
      opacity: 1;
    }
    75% {
      transform: scale(1);
      opacity: 1;
    }
    100% {
      transform: scale(0.92);
      filter: blur(1.5px);
      opacity: 0;
    }
  }

  @keyframes bat-swing {
    0% {
      transform: rotate(55deg) translate(0, 0);
    }
    65% {
      transform: rotate(-18deg) translate(12px, -22px);
    }
    100% {
      transform: rotate(-30deg) translate(20px, -28px);
      opacity: 0;
    }
  }

  @keyframes bat-impact {
    0% {
      opacity: 0;
      transform: translate(-50%, -50%) scale(0.1);
    }
    35% {
      opacity: 1;
    }
    100% {
      opacity: 0;
      transform: translate(-50%, -50%) scale(5.2);
    }
  }

  @keyframes ball-launch {
    0% {
      transform: translate(-50%, -50%) scale(1);
      opacity: 1;
    }
    20% {
      transform: translate(20px, -26px) scale(1.03);
      opacity: 1;
    }
    100% {
      transform: translate(120vw, -58vh) scale(0.35);
      opacity: 0;
    }
  }

  @media (max-width: 520px) {
    .obs-container {
      padding: 10px;
    }

    .score-stack {
      width: min(100%, 100vw - 20px);
    }

    .status-row {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .team-row {
      min-height: 56px;
      padding: 0.5rem 0.65rem;
    }

    .team-score {
      min-width: 50px;
      font-size: 1.7rem;
    }

    .team-short {
      font-size: 1rem;
    }

    .team-long,
    .status-subvalue {
      font-size: 0.62rem;
    }
  }
</style>
