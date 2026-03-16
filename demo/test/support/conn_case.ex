defmodule DemoWeb.ConnCase do
  @moduledoc false

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint DemoWeb.Endpoint

      import Plug.Conn
      import Phoenix.ConnTest
      import DemoWeb.ConnCase

      use Phoenix.VerifiedRoutes,
        endpoint: DemoWeb.Endpoint,
        router: DemoWeb.Router,
        statics: DemoWeb.static_paths()
    end
  end
end
