defmodule DemoWeb.PageController do
  use DemoWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: {DemoWeb.Layouts, :app})
  end

  def about(conn, _params) do
    render(conn, :about, layout: {DemoWeb.Layouts, :app})
  end

  def features(conn, _params) do
    render(conn, :features, layout: {DemoWeb.Layouts, :app})
  end

  def contact(conn, _params) do
    render(conn, :contact, layout: {DemoWeb.Layouts, :app})
  end

  def dashboard(conn, _params) do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)
    uptime_hours = div(uptime_ms, 3_600_000)
    uptime_mins = div(rem(uptime_ms, 3_600_000), 60_000)

    render(conn, :dashboard,
      layout: {DemoWeb.Layouts, :app},
      uptime: "#{uptime_hours}h #{uptime_mins}m",
      process_count: :erlang.system_info(:process_count) |> Integer.to_string(),
      memory_mb:
        (:erlang.memory(:total) / 1_048_576)
        |> Float.round(1)
        |> Float.to_string(),
      server_time: DateTime.utc_now() |> Calendar.strftime("%H:%M:%S UTC"),
      node: Node.self() |> Atom.to_string()
    )
  end
end
