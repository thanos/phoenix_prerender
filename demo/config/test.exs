import Config

config :demo, DemoWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base:
    "demo_test_secret_key_base_that_is_at_least_64_bytes_long_for_phoenix_prerender_demo_app",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime
