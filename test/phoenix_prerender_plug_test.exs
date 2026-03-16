defmodule PhoenixPrerender.PlugTest do
  use PhoenixPrerenderWeb.ConnCase, async: false

  alias PhoenixPrerender.Plug, as: PrerenderPlug

  @output_path "test/tmp/plug_prerendered"

  setup do
    File.rm_rf!(@output_path)
    File.mkdir_p!(@output_path)

    on_exit(fn -> File.rm_rf!(@output_path) end)

    :ok
  end

  defp write_prerendered(path, content, style \\ :dir_index) do
    file = PhoenixPrerender.Path.full_output_path(path, @output_path, style)
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, content)
  end

  defp call_plug(conn, opts \\ []) do
    opts =
      Keyword.merge(
        [output_path: @output_path, enabled: true, url_style: :dir_index],
        opts
      )

    plug_opts = PrerenderPlug.init(opts)
    PrerenderPlug.call(conn, plug_opts)
  end

  describe "serving prerendered pages" do
    test "serves prerendered page when file exists" do
      write_prerendered("/about", "<html>About Page</html>")

      conn =
        build_conn(:get, "/about")
        |> call_plug()

      assert conn.halted
      assert conn.status == 200
      assert get_resp_header(conn, "x-prerendered") == ["true"]
      assert get_resp_header(conn, "cache-control") == ["public, max-age=300"]
    end

    test "passes through when file does not exist" do
      conn =
        build_conn(:get, "/nonexistent")
        |> call_plug()

      refute conn.halted
    end

    test "passes through when disabled" do
      write_prerendered("/about", "<html>About</html>")

      conn =
        build_conn(:get, "/about")
        |> call_plug(enabled: false)

      refute conn.halted
    end

    test "serves root page" do
      write_prerendered("/", "<html>Home</html>")

      conn =
        build_conn(:get, "/")
        |> call_plug()

      assert conn.halted
      assert conn.status == 200
    end

    test "serves nested path" do
      write_prerendered("/docs/terms", "<html>Terms</html>")

      conn =
        build_conn(:get, "/docs/terms")
        |> call_plug()

      assert conn.halted
    end
  end

  describe "security" do
    test "rejects path traversal" do
      conn =
        build_conn(:get, "/about/../../../etc/passwd")
        |> call_plug()

      refute conn.halted
    end
  end

  describe "url_style :file" do
    test "serves with file style" do
      write_prerendered("/about", "<html>About</html>", :file)

      conn =
        build_conn(:get, "/about")
        |> call_plug(url_style: :file)

      assert conn.halted
      assert conn.status == 200
    end
  end
end
