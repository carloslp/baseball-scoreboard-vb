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
  let atBatStats = []
  let currentAtBatStats = null

  const AT_BAT_STATS_URL = 'https://script.google.com/macros/s/AKfycby7mLKmo5tYeyah3g75xA9FS48FPDbq6SJMkFDPErFi9dgrNAvlOEeapwTQ2fZTlHZg/exec?token=dads-12w1-dd3f-da1g&id=1r56WDn_pgZwoAHiiWmeaadUe1hepXC3Mo4t4PWwwfbQ&hoja=AVG-Activo'

  $: token = $page.params.token || ''
  $: currentAtBatStats = getAtBatStats(match?.at_bat_text)

  onMount(async () => {
    await Promise.all([loadMatch(), loadAtBatStats()])
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
    }, 10000)
  }

  /** @param {string | null | undefined} name */
  function getShortBatterName(name) {
    const parts = (name || '').trim().replace(/\s+/g, ' ').split(' ').filter(Boolean)
    if (parts.length === 0) return ''
    if (parts.length === 1) return parts[0]
    return `${parts[0]} ${parts[1]}`
  }

  /** @param {string | null | undefined} name */
  function normalizeName(name) {
    return (name || '').trim().replace(/\s+/g, ' ').toLowerCase()
  }

  async function loadAtBatStats() {
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
    }
  }

  /** @param {string | null | undefined} name */
  function getAtBatStats(name) {
    const normalized = normalizeName(name)
    if (!normalized) return null
    return atBatStats.find((item) => (
      normalizeName(item.shortName) === normalized
      || normalizeName(item.fullName) === normalized
    )) || null
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
        <div class="league-box">CDC</div>

        <div class="team-box">
          <span class="team-short">{getTeamParts(match.away_team_name).short}</span>
          <span class="team-long">{getTeamParts(match.away_team_name).long}</span>
        </div>
        <div class="score-box">{match.away_score}</div>
        <div class="score-separator"></div>
        <div class="team-box">
          <span class="team-short">{getTeamParts(match.home_team_name).short}</span>
          <span class="team-long">{getTeamParts(match.home_team_name).long}</span>
        </div>
        <div class="score-box">{match.home_score}</div>

        {#if match.obs_show_count !== false}
          <div class="inning-box">
            <span class="half-arrow">{match.inning_half === 'top' ? '▲' : '▼'}</span>
            <span class="inning-text">{getOrdinal(match.inning)}</span>
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
            <div class="outs-pips">
              {#each Array(3) as _, i}
                <span class="out-pip {i < match.outs ? 'filled' : ''}"></span>
              {/each}
            </div>
            <span class="outs-caption">{getOutsLabel(match.outs)}</span>
          </div>
        {/if}

        {#if match.obs_show_diamond !== false}
          <div class="diamond-box">
            <svg class="bases-svg" viewBox="-6 -6 112 112" role="img" aria-label="Baseball diamond">
              <polygon points="50,2 98,50 50,98 2,50" fill="rgba(255,255,255,0.03)" stroke="rgba(255,255,255,0.1)" stroke-width="1.25"/>
              <polygon points="50,-4 60,6 50,16 40,6"
                fill={match.base2 ? '#ffc800' : 'rgba(255,255,255,0.1)'}
                stroke={match.base2 ? '#ffe37a' : 'rgba(255,255,255,0.1)'}
                stroke-width="1.8"/>
              <polygon points="84,50 94,40 104,50 94,60"
                fill={match.base1 ? '#ffc800' : 'rgba(255,255,255,0.1)'}
                stroke={match.base1 ? '#ffe37a' : 'rgba(255,255,255,0.1)'}
                stroke-width="1.8"/>
              <polygon points="-4,50 6,40 16,50 6,60"
                fill={match.base3 ? '#ffc800' : 'rgba(255,255,255,0.1)'}
                stroke={match.base3 ? '#ffe37a' : 'rgba(255,255,255,0.1)'}
                stroke-width="1.8"/>
              <circle cx="50" cy="50" r="4" fill="rgba(255,255,255,0.2)" />
            </svg>
          </div>
        {/if}
      </div>



      {#if showAtBatBanner && match.at_bat_text}
        <div class="at-bat-strip {showAtBatBanner ? 'live' : ''}">
          <span class="at-bat-label">NOW BATTING</span>
          <span class="at-bat-name">{getShortBatterName(match.at_bat_text)}{#if currentAtBatStats} · AB {currentAtBatStats.AB} · H {currentAtBatStats.H} · HR {currentAtBatStats.HR} · K {currentAtBatStats.K} · AVG {currentAtBatStats.AVG}{/if}</span>
        </div>
      {/if}

      {#if bannerRotationSlots[currentBannerSlotIndex]}
        <div class="banner-strip">
          <img
            src={bannerRotationSlots[currentBannerSlotIndex]}
            alt="Advertising banner"
            class="banner-inline-img"
            width="450"
            height="100"
          />
        </div>
      {/if}

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
    align-items: flex-end;
    gap: 0;
    width: min(100%, 592px);
  }

  .score-bug {
    display: inline-flex;
    align-items: stretch;
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
    align-items: center;
    display: flex;
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

  .bases-svg {
    width: 34px;
    height: 34px;
    overflow: visible;
  }

  .diamond-box {
    justify-content: center;
    min-width: 54px;
    padding: 0 10px;
    background: linear-gradient(180deg, #121923 0%, #0a1019 100%);
    border-left: 1px solid rgba(255,255,255,0.04);
  }

  .banner-strip {
    align-self: flex-end;
    animation: panel-enter 0.35s ease-out;
  }

  .banner-inline-img {
    width: min(450px, 100%);
    height: 100px;
    object-fit: cover;
    display: block;
    border-radius: 8px;
    border: 1px solid rgba(255,255,255,0.25);
    box-shadow: 0 6px 20px rgba(0, 0, 0, 0.45);
  }

  .at-bat-strip {
    display: flex;
    align-items: center;
    justify-content: flex-start;
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
    animation: panel-enter 0.35s ease-out;
  }

  .at-bat-strip.live {
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
      width: 100%;
    }

    .score-bug {
      transform-origin: top right;
      transform: scale(0.82);
      margin-right: -48px;
    }

    .at-bat-strip {
      transform-origin: top right;
      transform: scale(0.82);
      margin-right: -1px;
      max-width: calc(100% - 140px);
    }
  }
</style>
