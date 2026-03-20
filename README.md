# PhoenixPrerender

Static prerendering and incremental static regeneration (ISR) for Phoenix applications.

Generate static HTML from your Phoenix routes at build time, serve them instantly from disk in production, and keep them fresh with background regeneration — similar to Next.js ISR or SvelteKit prerendering, but built for the BEAM.

See the features in action at the [**Live demo**](https://demo-muddy-river-958.fly.dev/)

## Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Guide](#guide)
  - [Configuration Guide](#configuration-guide)
  - [How Generation Works](#how-generation-works)
  - [URL Styles](#url-styles)
  - [The Serving Plug](#the-serving-plug)
  - [Incremental Static Regeneration (ISR)](#incremental-static-regeneration-isr)
  - [Distributed Regeneration](#distributed-regeneration)
  - [Page Cache](#page-cache)
  - [Cache Prewarming](#cache-prewarming)
  - [Static Asset Path Helper](#static-asset-path-helper)
  - [Pre-Compression](#pre-compression)
  - [Mix Task](#mix-task)
  - [Telemetry](#telemetry)
  - [Manifest & Sitemap](#manifest--sitemap)
  - [CI Integration](#ci-integration)
  - [LiveView Compatibility](#liveview-compatibility)
- [Performance](#performance)
- [Module Reference](#module-reference)
- [Roadmap](#roadmap)
- [License](#license)

## Features

- **Build-time static generation** — render marked routes through the full Phoenix endpoint pipeline and write HTML to disk
- **Plug-based serving** — intercept requests and serve prerendered files before they hit the router
- **Incremental static regeneration** — serve stale pages instantly while regenerating in the background
- **Thundering herd prevention** — ETS-based locks ensure only one regeneration per path
- **Distributed regeneration** — cluster-wide locking via `:global.trans/2` and cache invalidation via Phoenix PubSub
- **Atomic writes** — write-then-rename prevents serving partially written files
- **Concurrent generation** — render pages in parallel with `Task.async_stream`
- **Manifest & sitemap** — automatic `manifest.json` and `sitemap.xml` generation
- **Pluggable pre-compression** — generate `.gz` and `.br` files at build time, serve with `Accept-Encoding` negotiation
- **Cache prewarming** — load prerendered pages into ETS on boot for zero first-request latency
- **Static asset path helper** — resolve digested asset paths (`/assets/app.css` → `/assets/app-ABC123.css`) in prerendered content
- **Telemetry** — events for generation, rendering, serving, regeneration, and prewarming
- **Mix task** — `mix phoenix.prerender` for CLI and CI integration
- **Router macro** — `prerender do ... end` block to annotate routes without repetition
- **Verified routes compatible** — generated files match canonical `~p` paths

## Quick Start

### 1. Add the dependency

```elixir
# mix.exs
defp deps do
  [
    {:phoenix_prerender, "~> 0.2.0"}
  ]
end
```

### 2. Mark routes for prerendering

In your router, mark routes with `metadata: %{prerender: true}`:

```elixir
# lib/my_app_web/router.ex
defmodule MyAppWeb.Router do
  use MyAppWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {MyAppWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", MyAppWeb do
    pipe_through :browser

    get "/about", PageController, :about, metadata: %{prerender: true}
    get "/pricing", PageController, :pricing, metadata: %{prerender: true}
    live "/docs/terms", TermsLive, metadata: %{prerender: true}

    # This route is NOT prerendered
    get "/contact", PageController, :contact
  end
end
```

Or use the `prerender` macro for cleaner syntax:

```elixir
import PhoenixPrerender

scope "/", MyAppWeb do
  pipe_through :browser

  prerender do
    get "/about", PageController, :about
    get "/pricing", PageController, :pricing
    live "/docs/terms", TermsLive
  end

  # Not prerendered
  get "/contact", PageController, :contact
end
```

### 3. Add the serving plug

Add `PhoenixPrerender.Plug` to your endpoint, **before** the router:

```elixir
# lib/my_app_web/endpoint.ex
defmodule MyAppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :my_app

  plug Plug.Static, ...

  # Serve prerendered pages when available
  plug PhoenixPrerender.Plug

  plug MyAppWeb.Router
end
```

### 4. Configure

```elixir
# config/prod.exs
config :phoenix_prerender,
  enabled: true
```

### 5. Generate

```bash
mix phoenix.prerender
```

That's it. Marked routes are rendered through your full endpoint pipeline and written as static HTML files. In production, `PhoenixPrerender.Plug` serves them directly.

## Configuration

All configuration lives under the `:phoenix_prerender` application key:

```elixir
config :phoenix_prerender,
  # Whether the serving plug is active (default: false)
  enabled: false,

  # Directory for generated HTML files (default: "priv/static/prerendered")
  output_path: "priv/static/prerendered",

  # How URL paths map to files (default: :dir_index)
  #   :dir_index → /about → about/index.html
  #   :file      → /about → about.html
  url_style: :dir_index,

  # Cache-Control header for served pages (default: "public, max-age=300")
  cache_control: "public, max-age=300",

  # Metadata key/value for route discovery (defaults: :prerender / true)
  route_private_key: :prerender,
  route_private_value: true,

  # Concurrent rendering tasks (default: System.schedulers_online())
  concurrency: System.schedulers_online(),

  # Enable incremental static regeneration (default: false)
  isr: false,

  # Seconds before a page is considered stale (default: 300)
  revalidate: 300,

  # ISR strategy (default: :stale_while_revalidate)
  strategy: :stale_while_revalidate,

  # Base URL for sitemap.xml (default: "https://example.com")
  base_url: "https://example.com",

  # PubSub server for distributed cache invalidation (default: nil)
  pubsub: nil,

  # Only serve paths listed in manifest.json (default: true)
  strict_paths: true,

  # Compressor modules for pre-compression (default: [])
  compressors: [],

  # Prewarm ETS cache from manifest on boot (default: false)
  prewarm: false
```

> **Note:** The `output_path` and `url_style` settings are shared between the
> mix task (which writes files) and the plug (which serves them). If you
> override either via CLI flags (`--output`, `--style`) without updating the
> config or plug options to match, the plug won't find the generated files.
> The safest approach is to set these values once in application config.

## Guide

### Configuration Guide

The [Configuration](#configuration) reference above lists every option with its default. This section explains how to combine them for common deployment scenarios.

#### Minimal production setup

The simplest production configuration enables the serving plug and sets a base URL for sitemap generation:

```elixir
# config/prod.exs
config :phoenix_prerender,
  enabled: true,
  base_url: "https://myapp.com"
```

Add the plug to your endpoint and run `mix phoenix.prerender` during your build. That's all you need for static serving.

#### ISR with cache prewarming

For sites that need pages to stay fresh without full rebuilds, enable ISR and prewarm the cache so the first request after a deploy is served from memory:

```elixir
# config/prod.exs
config :phoenix_prerender,
  enabled: true,
  isr: true,
  revalidate: 300,
  prewarm: true,
  base_url: "https://myapp.com"
```

```elixir
# lib/my_app/application.ex
children = [
  MyAppWeb.Endpoint,
  {PhoenixPrerender.PageCache, prewarm: true},
  {PhoenixPrerender.Regenerator, endpoint: MyAppWeb.Endpoint}
]
```

On boot, `PageCache` reads the manifest, loads all pages into ETS, and logs the count. ISR then keeps them fresh in the background.

#### Pre-compression for bandwidth savings

Enable gzip pre-compression to generate `.gz` files at build time. The plug serves them automatically when the client supports it:

```elixir
# config/config.exs
config :phoenix_prerender,
  compressors: [PhoenixPrerender.Compressor.Gzip]
```

For Brotli, implement the `PhoenixPrerender.Compressor` behaviour (see [Pre-Compression](#pre-compression)) and add your module to the list. The plug prefers `br` over `gzip` when both are available.

#### Multi-node cluster

For distributed deployments, add PubSub so cache invalidations propagate across nodes:

```elixir
# config/prod.exs
config :phoenix_prerender,
  enabled: true,
  isr: true,
  revalidate: 300,
  prewarm: true,
  pubsub: MyApp.PubSub,
  base_url: "https://myapp.com",
  compressors: [PhoenixPrerender.Compressor.Gzip]
```

See [Distributed Regeneration](#distributed-regeneration) for supervision tree setup.

#### Development

In development, prerendering is disabled by default (`enabled: false`). You can still generate pages for testing:

```bash
mix phoenix.prerender --path /about
```

The static asset path helper gracefully returns the original path when the endpoint has no static manifest configured, so templates work without changes between dev and prod.

#### Per-environment overrides

Some settings make sense to vary by environment:

| Setting | Dev | Test | Prod |
|---|---|---|---|
| `enabled` | `false` | `false` | `true` |
| `prewarm` | `false` | `false` | `true` |
| `compressors` | `[]` | `[]` | `[Compressor.Gzip]` |
| `isr` | `false` | `false` | `true` / `false` |
| `output_path` | default | test-specific | default |

### How Generation Works

When you run `mix phoenix.prerender`, the generator:

1. **Discovers routes** — calls `Phoenix.Router.routes/1` and filters for routes with `metadata: %{prerender: true}`
2. **Renders each route** — builds a `Plug.Conn`, sets `accept: text/html`, and dispatches through the full endpoint pipeline using `Phoenix.ConnTest.dispatch/5`
3. **Writes HTML to disk** — uses atomic writes (write to `.tmp`, then rename) to prevent serving partially written files
4. **Generates manifest** — writes `manifest.json` with checksums, file sizes, and timestamps for each page
5. **Generates sitemap** — writes `sitemap.xml` with absolute URLs for all generated pages

Generation is concurrent — pages are rendered in parallel using `Task.async_stream` with configurable concurrency.

### URL Styles

Two styles control how URL paths map to files on disk:

| Style | URL Path | File Path |
|---|---|---|
| `:dir_index` (default) | `/about` | `about/index.html` |
| `:dir_index` | `/` | `index.html` |
| `:file` | `/about` | `about.html` |
| `:file` | `/` | `index.html` |

### The Serving Plug

`PhoenixPrerender.Plug` runs in your endpoint before the router. For each request it:

1. Checks if prerendering is enabled (skips if disabled)
2. Normalizes the request path (strips trailing slashes)
3. Validates path safety (rejects directory traversal attempts)
4. Looks up the expected file path on disk
5. If the file exists, serves it with `send_file` and halts
6. If not, passes through to the rest of the pipeline

Served responses include these headers:

- `content-type: text/html`
- `cache-control: public, max-age=300` (configurable)
- `x-prerendered: true` (useful for debugging)

You can override options per-plug:

```elixir
plug PhoenixPrerender.Plug,
  output_path: "priv/static/prerendered",
  url_style: :dir_index,
  cache_control: "public, max-age=3600",
  enabled: true
```

### Incremental Static Regeneration (ISR)

ISR keeps prerendered pages fresh without full rebuilds. Enable it with:

```elixir
# config/prod.exs
config :phoenix_prerender,
  enabled: true,
  isr: true,
  revalidate: 300  # seconds
```

Add the required processes to your supervision tree:

```elixir
# lib/my_app/application.ex
children = [
  MyAppWeb.Endpoint,
  PhoenixPrerender.PageCache,
  {PhoenixPrerender.Regenerator, endpoint: MyAppWeb.Endpoint}
]
```

**How ISR works:**

1. A request comes in for `/about`
2. The plug finds `about/index.html` on disk and serves it immediately
3. If the file is older than `revalidate` seconds, a background task is spawned
4. The background task re-renders the page and writes the fresh HTML to disk
5. An ETS lock prevents multiple processes from regenerating the same page
6. The next request gets the fresh content

This is the **stale-while-revalidate** pattern — users always get an instant response, and the content converges to fresh.

### Distributed Regeneration

When running on multiple BEAM nodes, use `PhoenixPrerender.Cluster` for
cluster-wide coordination:

```elixir
# config/prod.exs
config :phoenix_prerender,
  pubsub: MyApp.PubSub
```

`PhoenixPrerender.Cluster.regenerate/4` uses `:global.trans/2` to ensure only one node regenerates a given page, then broadcasts via PubSub so all nodes invalidate their local caches.

Subscribe in a GenServer to react to cross-node regenerations:

```elixir
def init(state) do
  PhoenixPrerender.Cluster.subscribe()
  {:ok, state}
end

def handle_info({:regenerated, path}, state) do
  PhoenixPrerender.Cluster.handle_regenerated(path)
  {:noreply, state}
end
```

### Page Cache

`PhoenixPrerender.PageCache` is an optional ETS-based in-memory cache that stores rendered HTML for even faster serving (avoiding disk reads):

```elixir
# Add to supervision tree
children = [
  PhoenixPrerender.PageCache
]
```

The cache supports:

- `get/1` — look up a page by path
- `put/3` — store a page with optional metadata
- `delete/1` — remove a single entry
- `clear/0` — flush all entries
- `stale?/2` — check if an entry is older than a threshold
- `size/0` — count cached entries

### Cache Prewarming

By default, the first request for each page incurs a disk read. Cache prewarming loads all pages from the manifest into ETS on boot, so every request is served from memory from the start.

```elixir
# config/prod.exs
config :phoenix_prerender,
  prewarm: true
```

```elixir
# lib/my_app/application.ex
children = [
  MyAppWeb.Endpoint,
  {PhoenixPrerender.PageCache, prewarm: true}
]
```

Prewarming uses `handle_continue`, so the supervisor does not block — the application starts immediately, and the ETS table is populated asynchronously. Requests that arrive before prewarming completes get a cache miss and fall back to disk, so there is no downtime window.

A `[:phoenix_prerender, :prewarm]` telemetry event is emitted with `%{duration: native_time, count: pages_loaded}` when prewarming completes.

Missing files are warned and skipped — a partially present output directory does not crash the application.

### Static Asset Path Helper

When prerendering at build time, templates may reference undigested asset paths. `PhoenixPrerender.StaticAsset.static_path/2` resolves `/assets/app.css` → `/assets/app-ABC123.css` using the endpoint's static manifest:

```elixir
PhoenixPrerender.static_asset_path(MyAppWeb.Endpoint, "/assets/app.css")
#=> "/assets/app-ABC123.css"
```

During `mix phoenix.prerender`, the endpoint is started (the task calls `app.start`), so this resolution works automatically. In dev mode or when the manifest is not configured, the original path is returned unchanged as a graceful fallback.

> **Note:** Phoenix's own `Endpoint.static_path/1` already works in templates
> during prerendering. This helper provides a standalone function for
> programmatic use and edge cases outside of templates.

### Pre-Compression

Pre-compression generates compressed variants of HTML files at build time (e.g., `about/index.html.gz`), so the serving plug can send them directly without on-the-fly compression overhead.

#### Enabling gzip pre-compression

```elixir
# config/config.exs
config :phoenix_prerender,
  compressors: [PhoenixPrerender.Compressor.Gzip]
```

This uses Erlang's built-in `:zlib` module — no NIF dependencies required. After generation, each page will have a `.gz` sibling:

```
priv/static/prerendered/
├── about/
│   ├── index.html
│   └── index.html.gz
```

#### Adding Brotli (or any custom compressor)

Compression is pluggable via the `PhoenixPrerender.Compressor` behaviour. Implement `compress/1` and `extension/0`:

```elixir
defmodule MyApp.BrotliCompressor do
  @behaviour PhoenixPrerender.Compressor

  @impl true
  def compress(content) do
    case ExBrotli.compress(content) do
      {:ok, compressed} -> {:ok, compressed}
      error -> {:error, error}
    end
  end

  @impl true
  def extension, do: ".br"
end
```

```elixir
config :phoenix_prerender,
  compressors: [PhoenixPrerender.Compressor.Gzip, MyApp.BrotliCompressor]
```

#### How serving works

When `PhoenixPrerender.Plug` serves a page from disk, it negotiates encoding:

1. Parses the `accept-encoding` request header
2. Checks for compressed files in preference order: `br` > `gzip` > identity
3. If a compressed file exists, serves it with `content-encoding` and `vary: accept-encoding` headers
4. If no compressed file exists, serves the uncompressed original

Cache-served responses (from ETS) are sent as-is without pre-compression headers. If your endpoint or web server (Cowboy/Bandit) is configured for response compression, it will compress these responses on the fly. Otherwise, they are served uncompressed.

Compressors are fault-tolerant: if a compressor fails, it logs a warning and is skipped. The uncompressed file is always written regardless.

### Mix Task

The `mix phoenix.prerender` (or `mix phx.prerender`) task provides CLI access to generation:

```bash
# Generate all prerender-marked routes
mix phx.prerender

# Specify router and endpoint explicitly
mix phx.prerender --router MyAppWeb.Router --endpoint MyAppWeb.Endpoint

# Regenerate only specific pages (can be repeated)
mix phx.prerender --path /about --path /docs/terms

# Use file-style URLs (about.html instead of about/index.html)
mix phx.prerender --style file

# Custom output directory
mix phx.prerender --output _build/prerendered

# Limit concurrency (useful on memory-constrained CI runners)
mix phx.prerender --concurrency 2
```

> **Important:** The `--output` and `--style` flags only affect where and how
> the task writes files. The serving plug must be configured to match,
> otherwise it will look in the wrong location or for the wrong filenames.
> Set these via application config so both the task and plug stay in sync:
>
> ```elixir
> config :phoenix_prerender,
>   output_path: "_build/prerendered",
>   url_style: :file
> ```

### Telemetry

PhoenixPrerender emits telemetry events at key lifecycle points:

| Event | When | Measurements | Metadata |
|---|---|---|---|
| `[:phoenix_prerender, :generate]` | After full generation run | `duration`, `count`, `successes`, `failures` | `output_path` |
| `[:phoenix_prerender, :render]` | After rendering a single page | `duration` | `path`, `status` |
| `[:phoenix_prerender, :serve]` | When serving a prerendered page | `duration` | `path`, `source` |
| `[:phoenix_prerender, :regenerate]` | After ISR regeneration | `duration` | `path`, `result` |
| `[:phoenix_prerender, :prewarm]` | After cache prewarming on boot | `duration`, `count` | `output_path` |

All durations are in native time units. Use with `Telemetry.Metrics`:

```elixir
def metrics do
  [
    summary("phoenix_prerender.generate.duration", unit: {:native, :millisecond}),
    counter("phoenix_prerender.serve.duration"),
    summary("phoenix_prerender.render.duration", unit: {:native, :millisecond}, tags: [:status])
  ]
end
```

Or attach the built-in debug logger:

```elixir
PhoenixPrerender.Telemetry.attach_default_logger()
```

### Manifest & Sitemap

After generation, two files are written to the output directory:

**`manifest.json`** — metadata for every generated page:

```json
{
  "generated_at": "2024-01-15T10:30:00Z",
  "pages": [
    {
      "route": "/about",
      "file": "priv/static/prerendered/about/index.html",
      "size": 4521,
      "checksum": "a1b2c3d4...",
      "generated_at": "2024-01-15T10:30:00Z"
    }
  ]
}
```

**`sitemap.xml`** — standard sitemaps.org format:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>https://example.com/about</loc>
    <lastmod>2024-01-15T10:30:00Z</lastmod>
  </url>
</urlset>
```

Read the manifest programmatically:

```elixir
{:ok, manifest} = PhoenixPrerender.Manifest.read("priv/static/prerendered")
page = PhoenixPrerender.Manifest.lookup(manifest, "/about")
page["checksum"]
```

### CI Integration

Add prerendering to your deployment pipeline:

```yaml
# .github/workflows/deploy.yml
- name: Generate prerendered pages
  run: |
    mix deps.get
    mix compile
    mix phoenix.prerender
    mix phx.digest
```

### LiveView Compatibility

LiveView routes work seamlessly with prerendering. The generator renders
the HTTP (non-WebSocket) path, producing static HTML that includes
`data-phx-session` and `data-phx-static` attributes. When the browser
loads the prerendered page and connects via WebSocket, LiveView hydrates
normally.

```elixir
prerender do
  live "/changelog", ChangelogLive
end
```

## Performance

Benchmarking the same `/about` page (10.6 KB) served three ways on Apple M1 Max:

| Serving Mode | Throughput | Avg Latency | Memory | vs Cache |
|---|---|---|---|---|
| **Prerendered (ETS cache)** | 5,000 req/s | 200 μs | 5.4 KB | — |
| **Prerendered (disk)** | 4,040 req/s | 248 μs | 8.3 KB | 1.24x slower |
| **Dynamic (full Phoenix pipeline)** | 45 req/s | 22,134 μs | 46.0 KB | **110x slower** |

Prerendered pages serve **~110x faster** with **~8.5x less memory** than rendering dynamically through the full Phoenix pipeline (router, controller, template). The ETS cache and disk paths perform similarly thanks to OS-level file caching.

Run the benchmark yourself:

```bash
cd demo && mix run bench/plug_serving_bench.exs
```

## Module Reference

| Module | Purpose |
|---|---|
| `PhoenixPrerender` | Main module, configuration, `prerender/1` macro |
| `PhoenixPrerender.Plug` | Serves prerendered files from disk with encoding negotiation |
| `PhoenixPrerender.Generator` | Concurrent page generation with atomic writes and pre-compression |
| `PhoenixPrerender.Renderer` | Renders routes through the endpoint pipeline |
| `PhoenixPrerender.StaticAsset` | Resolves digested asset paths via endpoint |
| `PhoenixPrerender.Compressor` | Behaviour and orchestrator for pluggable pre-compression |
| `PhoenixPrerender.Compressor.Gzip` | Built-in gzip compressor using `:zlib` (no NIF) |
| `PhoenixPrerender.Route` | Discovers prerender-marked routes |
| `PhoenixPrerender.Path` | URL-to-filesystem path mapping |
| `PhoenixPrerender.Manifest` | Manifest and sitemap read/write |
| `PhoenixPrerender.PageCache` | ETS-based in-memory page cache with optional prewarming |
| `PhoenixPrerender.Regenerator` | ISR with ETS-based lock management |
| `PhoenixPrerender.Cluster` | Distributed regeneration via `:global` and PubSub |
| `PhoenixPrerender.Telemetry` | Telemetry event definitions and default logger |
| `Mix.Tasks.Phoenix.Prerender` | Mix task for CLI generation |

## Roadmap

### v0.2.0 — Optimizations & Developer Experience ✅

- ~~**Static asset path helper** — a `static_asset_path/2` function for resolving digested asset paths inside prerendered templates~~
- ~~**Gzip & Brotli pre-compression** — generate `.gz` and `.br` files alongside HTML for zero-overhead compressed serving~~
- ~~**Cache prewarm on boot** — automatically load prerendered pages from disk into ETS on application start~~

### v0.3.0 — Distributed Consistency & Cache Control

- **PubSub invalidation** — integrate Phoenix.PubSub for cluster-wide cache purging (e.g., `PhoenixPrerender.purge("/blog/post-1")` clears ETS on all nodes)
- **Tag-based purging** — support metadata tags on routes (e.g., `tags: [:author_1, :sidebar]`) to allow bulk invalidation of related content
- **Header preservation** — store and serve original `content-security-policy`, `cache-control`, and `x-frame-options` headers from the prerendered manifest

### v0.4.0 — Enhanced Hybrid DX

- **Dev-mode proxy** — a Plug that simulates prerendering in development without writing to disk, providing headers and latency logs in the console
- **LiveView Dashboard integration** — a custom card for `Phoenix.LiveDashboard` to monitor cache hits, misses, and manual purge controls
- **Selective hydration support** — attributes to mark specific DOM elements to be excluded from prerendering (e.g., `data-prerender-ignore`) to prevent flickering of user-specific data

### v0.5.0 — Performance & Edge Optimization

- **Pre-compressed assets** — store `.gz` and `.br` (Brotli) versions of HTML in ETS/storage to enable zero-copy serving via Plug
- **Image optimization pipeline** — a built-in task to scan prerendered HTML and generate optimized `srcset` images for local assets
- **SWR background workers** — Broadway or GenStage integration to stagger background regenerations during high-traffic spikes

### v0.6.0 — Persistence & Distribution

- **External cache adapters** — a behaviour-based adapter system moving beyond local ETS:
  - Nebulex/Cachex for distributed, multi-level caching (L1/L2) across nodes
  - Redis for persistence across application restarts
- **Storage providers** — a `PhoenixPrerender.Store` behaviour for uploading prerendered HTML and assets to S3, GCS, or Azure
- **CDN invalidation** — hooks to trigger `PURGE` requests to Cloudflare or Fastly after regeneration

### v0.7.0 — Workflow Automation & Orchestration

- **Scheduled prerendering (Quantum)** — first-class support for Quantum cron expressions to trigger full or partial site warm-ups (e.g., prerender the "Daily News" section every morning at 6:00 AM)
- **Resilient image pipeline (Oban)** — use Oban for background image processing (WebP/AVIF generation) with retries, rate-limiting, and observability
- **Extended telemetry** — emit `[:phoenix_prerender, :render, :stop]` events to allow developers to track prerendering duration and identify bottlenecks

## License

MIT
