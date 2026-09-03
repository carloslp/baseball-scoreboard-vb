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

  $: token = $page.params.token

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

  function getOrdinal(number) {
    const lastTwoDigits = number % 100
    if (lastTwoDigits >= 11 && lastTwoDigits <= 13) return number + 'th'
    const lastDigit = number % 10
    return number + (['th','st','nd','rd'][lastDigit] || 'th')
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
        <div class="teams">
          <div class="team-row" style="--color: {match.away_team_color}">
            <span class="team-name">{match.away_team_name}</span>
            <span class="team-score">{match.away_score}</span>
          </div>
          <div class="divider"></div>
          <div class="team-row" style="--color: {match.home_team_color}">
            <span class="team-name">{match.home_team_name}</span>
            <span class="team-score">{match.home_score}</span>
          </div>
        </div>

        {#if match.obs_show_count !== false}
        <div class="game-info">
          <div class="inning-info">
            <span class="half-arrow">{match.inning_half === 'top' ? '▲' : '▼'}</span>
            <span class="inning-text">{getOrdinal(match.inning)}</span>
          </div>
          <div class="count-info">
            <div class="count-section">
              <span class="count-val balls">{match.balls}</span>
              <span class="count-lbl">B</span>
            </div>
            <span class="count-sep">·</span>
            <div class="count-section">
              <span class="count-val strikes">{match.strikes}</span>
              <span class="count-lbl">S</span>
            </div>
            <span class="count-sep">·</span>
            <div class="count-section">
              <span class="count-val outs">{match.outs}</span>
              <span class="count-lbl">O</span>
            </div>
          </div>
          <div class="outs-pips">
            {#each Array(3) as _, i}
              <span class="out-pip {i < match.outs ? 'filled' : ''}"></span>
            {/each}
          </div>
        </div>
        {/if}

        {#if match.obs_show_diamond !== false}
        <div class="bases-col">
          <svg class="bases-svg" viewBox="-6 -6 112 112" role="img" aria-label="Baseball diamond">
            <polygon points="50,2 98,50 50,98 2,50" fill="none" stroke="rgba(255,255,255,0.18)" stroke-width="1.5"/>
            <polygon points="50,88 56,94 50,100 44,94" fill="rgba(255,255,255,0.25)"/>
            <polygon points="50,-4 56,2 50,8 44,2"
              fill={match.base2 ? '#f0c040' : 'rgba(255,255,255,0.08)'}
              stroke={match.base2 ? '#f0c040' : 'rgba(255,255,255,0.35)'}
              stroke-width="2"/>
            <polygon points="88,50 98,42 106,50 98,58"
              fill={match.base1 ? '#f0c040' : 'rgba(255,255,255,0.08)'}
              stroke={match.base1 ? '#f0c040' : 'rgba(255,255,255,0.35)'}
              stroke-width="2"/>
            <polygon points="-6,50 2,42 10,50 2,58"
              fill={match.base3 ? '#f0c040' : 'rgba(255,255,255,0.08)'}
              stroke={match.base3 ? '#f0c040' : 'rgba(255,255,255,0.35)'}
              stroke-width="2"/>
          </svg>
        </div>
        {/if}
      </div>
      {#if showAtBatBanner && match.at_bat_text}
        <div class="at-bat-strip">
          <span class="at-bat-label">NOW BATTING</span>
          <span class="at-bat-name">{match.at_bat_text}</span>
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
    align-items: stretch;
    gap: 6px;
  }

  .at-bat-strip {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 0.55rem;
    background: linear-gradient(135deg, rgba(5,18,42,0.96), rgba(14,40,79,0.96));
    border: 1px solid rgba(255,255,255,0.28);
    border-radius: 8px;
    padding: 0.4rem 0.75rem;
    box-shadow: 0 6px 20px rgba(0, 0, 0, 0.45);
    animation: at-bat-enter 0.35s ease-out;
  }

  .at-bat-label {
    color: #c9d8ff;
    font-size: 0.58rem;
    font-weight: 900;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    opacity: 0.95;
  }

  .at-bat-name {
    color: #ffffff;
    font-size: 0.82rem;
    font-weight: 900;
    letter-spacing: 0.05em;
    text-transform: uppercase;
    max-width: 330px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  @keyframes at-bat-enter {
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

  .banner-strip {
    align-self: flex-end;
    animation: at-bat-enter 0.35s ease-out;
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

  .score-bug {
    position: relative;
    display: flex;
    flex-direction: row;
    align-items: stretch;
    background: linear-gradient(135deg, rgba(5,18,42,0.96), rgba(14,40,79,0.96));
    border: 1px solid rgba(255,255,255,0.28);
    border-radius: 8px;
    overflow: hidden;
    backdrop-filter: blur(10px);
    box-shadow: 0 10px 26px rgba(0,0,0,0.56);
    min-width: 280px;
  }

  .score-bug::before {
    content: '';
    position: absolute;
    top: 0;
    left: 0;
    right: 0;
    height: 2px;
    background: linear-gradient(90deg, #d90429 0%, #ffffff 50%, #0a4db3 100%);
    opacity: 0.9;
    pointer-events: none;
  }

  .teams {
    display: flex;
    flex-direction: column;
    border-right: 1px solid rgba(255,255,255,0.14);
  }

  .team-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.9rem;
    padding: 0.45rem 0.75rem;
  }

  .divider {
    height: 1px;
    background: rgba(255,255,255,0.08);
    margin: 0 0.5rem;
  }

  .team-name {
    font-size: 0.74rem;
    font-weight: 900;
    text-transform: uppercase;
    letter-spacing: 0.07em;
    color: #ffffff;
    text-shadow: 0 0 8px rgba(255, 255, 255, 0.18);
    min-width: 40px;
  }

  .team-score {
    font-size: 1.2rem;
    font-weight: 900;
    color: #FFE600;
    font-variant-numeric: tabular-nums;
    min-width: 1.5rem;
    text-align: right;
    line-height: 1;
    text-shadow: 0 0 10px rgba(255, 230, 0, 0.38);
  }

  .game-info {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 0.45rem 0.72rem;
    gap: 0.24rem;
    background: rgba(0,0,0,0.2);
  }

  .inning-info {
    display: flex;
    align-items: center;
    gap: 0.25rem;
    color: #fff;
  }

  .half-arrow {
    font-size: 0.6rem;
    color: #f0c040;
  }

  .inning-text {
    font-size: 0.78rem;
    font-weight: 900;
    color: #ffffff;
    letter-spacing: 0.03em;
  }

  .count-info {
    display: flex;
    align-items: center;
    gap: 0.2rem;
  }

  .count-section {
    display: flex;
    align-items: baseline;
    gap: 1px;
  }

  .count-val {
    font-size: 0.88rem;
    font-weight: 900;
    font-variant-numeric: tabular-nums;
  }

  .count-val.balls { color: #00FF7F; }
  .count-val.strikes { color: #FFE600; }
  .count-val.outs { color: #FF5555; }

  .count-lbl {
    font-size: 0.55rem;
    font-weight: 800;
    color: #aaaaaa;
    text-transform: uppercase;
  }

  .count-sep {
    color: rgba(255,255,255,0.2);
    font-size: 0.7rem;
  }

  .outs-pips {
    display: flex;
    gap: 3px;
  }

  .bases-col {
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 0.45rem 0.72rem;
    border-left: 1px solid rgba(255,255,255,0.14);
    background: rgba(0,0,0,0.16);
  }

  .bases-svg {
    width: 44px;
    height: 44px;
    overflow: visible;
  }

  .out-pip {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    border: 1.5px solid rgba(248,113,113,0.4);
    background: transparent;
    transition: background 0.15s;
  }

  .out-pip.filled {
    background: #f87171;
    border-color: #f87171;
  }
</style>
