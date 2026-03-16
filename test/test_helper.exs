# Start the test host application (PhoenixPrerenderWeb.Endpoint, PubSub, etc.)
{:ok, _} = PhoenixPrerender.Application.start(:normal, [])

ExUnit.start()
