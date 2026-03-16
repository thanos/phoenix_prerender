import Config

config :phoenix_prerender, PhoenixPrerenderWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "jxHKHIMLkKz9hd5YGl1kY/AkoiK5ionAwNYm2BBbwQeiN3FVlu9zFgnZoyJsCqY7",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:phoenix_prerender, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:phoenix_prerender, ~w(--watch)]}
  ]

# Reload browser tabs when matching files change.
config :phoenix_prerender, PhoenixPrerenderWeb.Endpoint,
  live_reload: [
    web_console_logger: true,
    patterns: [
      ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"priv/gettext/.*\.po$",
      ~r"lib/phoenix_prerender_web/router\.ex$",
      ~r"lib/phoenix_prerender_web/(controllers|live|components)/.*\.(ex|heex)$"
    ]
  ]

# Enable dev routes for dashboard and mailbox
config :phoenix_prerender, dev_routes: true

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  debug_attributes: true,
  enable_expensive_runtime_checks: true
