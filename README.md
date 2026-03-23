# Baseball Scoreboard

A real-time baseball scoreboard web app built with SvelteKit and Supabase. Manage live game scores from a dashboard and broadcast them via a transparent OBS overlay.

## Features

- **Dashboard** — Control panel to manage home/away scores, balls, strikes, outs, and inning. Team names and colors are customizable.
- **OBS Overlay** — Transparent "score bug" overlay at `/obs/[token]` that updates in real-time via Supabase Realtime.
- **Authentication** — Email/password login and registration via Supabase Auth.
- **Auto inning advance** — Recording the 3rd out automatically advances the inning half and resets the count.

## Tech Stack

- [SvelteKit](https://kit.svelte.dev/) + Vite
- [Supabase](https://supabase.com/) — PostgreSQL database, Auth, and Realtime

## Setup

### 1. Supabase project

1. Create a project at [supabase.com](https://supabase.com).
2. Run the SQL in `supabase/schema.sql` in the Supabase SQL editor to create the `matches` table and RLS policies.

### 2. Environment variables

Copy `.env.example` to `.env` and fill in your Supabase credentials:

```sh
cp .env.example .env
```

```
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=your-anon-key
```

### 3. Install and run

```sh
npm install
npm run dev
```

## Routes

| Route | Description |
|-------|-------------|
| `/` | Redirects to `/dashboard` (authenticated) or `/login` |
| `/login` | Login / register |
| `/dashboard` | Protected match control panel |
| `/obs/[token]` | Public transparent OBS overlay |

## Building

```sh
npm run build
npm run preview
```

> To deploy, install a [SvelteKit adapter](https://svelte.dev/docs/kit/adapters) for your target environment.
