defmodule PhoenixPrerender.Repo do
  use Ecto.Repo,
    otp_app: :phoenix_prerender,
    adapter: Ecto.Adapters.Postgres
end
