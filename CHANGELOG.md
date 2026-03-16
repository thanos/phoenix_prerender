# Changelog

All notable changes to this project will be documented in this file.

## v0.1.0 (2026-03-16)

Initial release.

### Added

- **Build-time static generation** via `mix phoenix.prerender` — renders marked routes through the full Phoenix endpoint pipeline and writes HTML to disk
- **`prerender` router macro** — wrap routes in `prerender do ... end` to mark them for generation
- **`PhoenixPrerender.Plug`** — serves prerendered pages from memory cache or disk before they hit the router
- **Incremental static regeneration (ISR)** — stale-while-revalidate pattern serves existing content instantly while regenerating in the background
- **`PhoenixPrerender.PageCache`** — ETS-based in-memory cache with read concurrency for fast serving
- **`PhoenixPrerender.Regenerator`** — background regeneration with ETS lock management to prevent thundering herd
- **`PhoenixPrerender.Cluster`** — distributed regeneration via `:global.trans/2` and cache invalidation via Phoenix PubSub
- **Atomic writes** — write to `.tmp` then rename to prevent serving partially written files
- **Concurrent generation** — parallel rendering with `Task.async_stream` and configurable concurrency
- **Manifest & sitemap** — automatic `manifest.json` and `sitemap.xml` generation
- **Strict paths** — only serve paths listed in `manifest.json` (enabled by default)
- **Two URL styles** — `:dir_index` (`about/index.html`) and `:file` (`about.html`)
- **Telemetry events** — `generate`, `render`, `serve`, and `regenerate` events
- **LiveView compatibility** — prerender LiveView routes with client-side hydration
- **Mix task** — `mix phoenix.prerender` with `--path`, `--style`, `--concurrency`, `--output` flags
