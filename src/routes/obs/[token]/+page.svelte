<svelte:options runes={false} />

<script>
  import { onMount, onDestroy } from 'svelte'
  import { page } from '$app/stores'
  import { supabase } from '$lib/supabase'

  let token = ''
  let match = null
  let loading = true
  let channel = null

  $: token = $page.params.token

  onMount(async () => {
    await loadMatch()
    subscribeToRealtime()
  })

  onDestroy(() => {
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
    } else {
      match = null
    }
    loading = false
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
              match = payload.new
            } else {
              match = null
            }
          } else if (payload.eventType === 'DELETE') {
            match = null
          }
        }
      )
      .subscribe()
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
    align-items: flex-end;
    justify-content: flex-end;
    min-height: 100vh;
    padding: 20px;
    background: transparent;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  }

  .score-bug {
    display: flex;
    flex-direction: row;
    align-items: stretch;
    background: rgba(10, 12, 20, 0.92);
    border: 1px solid rgba(255,255,255,0.12);
    border-radius: 8px;
    overflow: hidden;
    backdrop-filter: blur(10px);
    box-shadow: 0 4px 24px rgba(0,0,0,0.5);
    min-width: 280px;
  }

  .teams {
    display: flex;
    flex-direction: column;
    border-right: 1px solid rgba(255,255,255,0.1);
  }

  .team-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0.4rem 0.75rem;
    gap: 1rem;
  }

  .divider {
    height: 1px;
    background: rgba(255,255,255,0.08);
    margin: 0 0.5rem;
  }

  .team-name {
    font-size: 0.75rem;
    font-weight: 800;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--color, #fff);
    min-width: 40px;
  }

  .team-score {
    font-size: 1.25rem;
    font-weight: 900;
    color: #fff;
    font-variant-numeric: tabular-nums;
    min-width: 1.5rem;
    text-align: right;
  }

  .game-info {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 0.4rem 0.75rem;
    gap: 0.25rem;
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
    font-size: 0.8rem;
    font-weight: 800;
    color: #fff;
    letter-spacing: 0.02em;
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
    font-size: 0.9rem;
    font-weight: 800;
    font-variant-numeric: tabular-nums;
  }

  .count-val.balls { color: #4ade80; }
  .count-val.strikes { color: #fbbf24; }
  .count-val.outs { color: #f87171; }

  .count-lbl {
    font-size: 0.55rem;
    font-weight: 700;
    color: #6b7280;
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
    padding: 0.4rem 0.75rem;
    border-left: 1px solid rgba(255,255,255,0.1);
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
