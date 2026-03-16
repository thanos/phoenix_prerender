import Config

config :phoenix_prerender, PhoenixPrerenderWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "7gxSatdPcoYif01OEVvjugvVp/Bzb855PHi7onXPBngutD03s24S7y0iP5yJwTzg",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  enable_expensive_runtime_checks: true

config :phoenix,
  sort_verified_routes_query_params: true
