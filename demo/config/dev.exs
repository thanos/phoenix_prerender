import Config

config :demo, DemoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4001],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base:
    "demo_dev_secret_key_base_that_is_at_least_64_bytes_long_for_phoenix_prerender_demo",
  watchers: []

config :phoenix_prerender,
  enabled: true,
  cache_control: "no-cache, no-store"

config :logger, :console, format: "[$level] $message\n"
config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
