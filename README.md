# PhoenixPrerender

Static prerendering and incremental static regeneration (ISR) for Phoenix applications.

Generate static HTML from your Phoenix routes at build time, serve them instantly from disk in production, and keep them fresh with background regeneration — similar to Next.js ISR or SvelteKit prerendering, but built for the BEAM.

## Features

- **Build-time static generation** — render marked routes through the full Phoenix endpoint pipeline and write HTML to disk
- **Plug-based serving** — intercept requests and serve prerendered files before they hit the router
- **Incremental static regeneration** — serve stale pages instantly while regenerating in the background
- **Thundering herd prevention** — ETS-based locks ensure only one regeneration per path
- **Distributed regeneration** — cluster-wide locking via `:global.trans/2` and cache invalidation via Phoenix PubSub
- **Atomic writes** — write-then-rename prevents serving partially written files
- **Concurrent generation** — render pages in parallel with `Task.async_stream`
- **Manifest & sitemap** — automatic `manifest.json` and `sitemap.xml` generation
- **Telemetry** — events for generation, rendering, serving, and regeneration
- **Mix task** — `mix phoenix.prerender` for CLI and CI integration
- **Router macro** — `prerender do ... end` block to annotate routes without repetition
- **Verified routes compatible** — generated files match canonical `~p` paths

## Quick Start

### 1. Add the dependency

```elixir
# mix.exs
defp deps do
  [
    {:phoenix_prerender, "~> 0.1.0"}
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
  pubsub: nil
```

## Guide

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

### Mix Task

The `mix phoenix.prerender` task provides CLI access to generation:

```bash
# Generate all prerender-marked routes
mix phoenix.prerender

# Specify router and endpoint
mix phoenix.prerender --router MyAppWeb.Router --endpoint MyAppWeb.Endpoint

# Generate specific pages only
mix phoenix.prerender --path /about --path /docs/terms

# Use file-style URLs
mix phoenix.prerender --style file

# Custom output directory
mix phoenix.prerender --output _build/prerendered

# Limit concurrency
mix phoenix.prerender --concurrency 2
```

### Telemetry

PhoenixPrerender emits telemetry events at key lifecycle points:

| Event | When | Measurements | Metadata |
|---|---|---|---|
| `[:phoenix_prerender, :generate]` | After full generation run | `duration`, `count`, `successes`, `failures` | `output_path` |
| `[:phoenix_prerender, :render]` | After rendering a single page | `duration` | `path`, `status` |
| `[:phoenix_prerender, :serve]` | When serving a prerendered page | `duration` | `path`, `source` |
| `[:phoenix_prerender, :regenerate]` | After ISR regeneration | `duration` | `path`, `result` |

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

## Module Reference

| Module | Purpose |
|---|---|
| `PhoenixPrerender` | Main module, configuration, `prerender/1` macro |
| `PhoenixPrerender.Plug` | Serves prerendered files from disk |
| `PhoenixPrerender.Generator` | Concurrent page generation with atomic writes |
| `PhoenixPrerender.Renderer` | Renders routes through the endpoint pipeline |
| `PhoenixPrerender.Route` | Discovers prerender-marked routes |
| `PhoenixPrerender.Path` | URL-to-filesystem path mapping |
| `PhoenixPrerender.Manifest` | Manifest and sitemap read/write |
| `PhoenixPrerender.PageCache` | ETS-based in-memory page cache |
| `PhoenixPrerender.Regenerator` | ISR with ETS-based lock management |
| `PhoenixPrerender.Cluster` | Distributed regeneration via `:global` and PubSub |
| `PhoenixPrerender.Telemetry` | Telemetry event definitions and default logger |
| `Mix.Tasks.Phoenix.Prerender` | Mix task for CLI generation |

## License

MIT
