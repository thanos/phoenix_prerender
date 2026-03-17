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
        [output_path: @output_path, enabled: true, url_style: :dir_index, strict_paths: false],
        opts
      )

    plug_opts = PrerenderPlug.init(opts)
    PrerenderPlug.call(conn, plug_opts)
  end

  defp write_manifest(entries) do
    PhoenixPrerender.Manifest.write(entries, @output_path)
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

  describe "cache serving" do
    setup do
      start_supervised!(PhoenixPrerender.PageCache)
      on_exit(fn -> PhoenixPrerender.PageCache.clear() end)
      :ok
    end

    test "serves from cache when page is cached" do
      PhoenixPrerender.PageCache.put("/cached", "<html>Cached Page</html>")

      conn =
        build_conn(:get, "/cached")
        |> call_plug()

      assert conn.halted
      assert conn.status == 200
      assert conn.resp_body == "<html>Cached Page</html>"
      assert get_resp_header(conn, "x-prerendered") == ["true"]
    end

    test "prefers cache over disk" do
      write_prerendered("/about", "<html>Disk Version</html>")
      PhoenixPrerender.PageCache.put("/about", "<html>Cache Version</html>")

      conn =
        build_conn(:get, "/about")
        |> call_plug()

      assert conn.halted
      assert conn.resp_body == "<html>Cache Version</html>"
    end

    test "falls back to disk when not in cache" do
      write_prerendered("/about", "<html>Disk Version</html>")

      conn =
        build_conn(:get, "/about")
        |> call_plug()

      assert conn.halted
      assert conn.status == 200
    end
  end

  describe "ISR stale-while-revalidate" do
    setup do
      start_supervised!(PhoenixPrerender.PageCache)
      start_supervised!({PhoenixPrerender.Regenerator, endpoint: PhoenixPrerenderWeb.Endpoint})

      # Enable ISR with a very short revalidation for testing
      original_isr = Application.get_env(:phoenix_prerender, :isr)
      original_revalidate = Application.get_env(:phoenix_prerender, :revalidate)

      Application.put_env(:phoenix_prerender, :isr, true)
      Application.put_env(:phoenix_prerender, :revalidate, 0)

      on_exit(fn ->
        if original_isr,
          do: Application.put_env(:phoenix_prerender, :isr, original_isr),
          else: Application.delete_env(:phoenix_prerender, :isr)

        if original_revalidate,
          do: Application.put_env(:phoenix_prerender, :revalidate, original_revalidate),
          else: Application.delete_env(:phoenix_prerender, :revalidate)

        PhoenixPrerender.PageCache.clear()
      end)

      :ok
    end

    test "serves stale file from disk and triggers regeneration" do
      write_prerendered("/about", "<html>Stale About</html>")

      # Make the file old by backdating mtime
      file_path = PhoenixPrerender.Path.full_output_path("/about", @output_path, :dir_index)
      File.touch!(file_path, {{2020, 1, 1}, {0, 0, 0}})

      conn =
        build_conn(:get, "/about")
        |> call_plug(endpoint: PhoenixPrerenderWeb.Endpoint)

      # Stale content is served immediately
      assert conn.halted
      assert conn.status == 200

      # Give background task a moment to run
      Process.sleep(100)
    end

    test "serves stale cache entry and triggers regeneration" do
      # Put a cache entry with an old cached_at timestamp
      old_time = System.monotonic_time() - System.convert_time_unit(600, :second, :native)
      PhoenixPrerender.PageCache.put("/about", "<html>Stale Cached</html>")

      # Manually backdate the cache entry
      :ets.insert(
        :phoenix_prerender_page_cache,
        {"/about", "<html>Stale Cached</html>", %{cached_at: old_time}}
      )

      conn =
        build_conn(:get, "/about")
        |> call_plug(endpoint: PhoenixPrerenderWeb.Endpoint)

      # Stale content is served immediately
      assert conn.halted
      assert conn.status == 200
      assert conn.resp_body == "<html>Stale Cached</html>"

      # Give background task a moment
      Process.sleep(100)
    end

    test "does not trigger regeneration when ISR disabled" do
      Application.put_env(:phoenix_prerender, :isr, false)

      write_prerendered("/about", "<html>About</html>")
      file_path = PhoenixPrerender.Path.full_output_path("/about", @output_path, :dir_index)
      File.touch!(file_path, {{2020, 1, 1}, {0, 0, 0}})

      conn =
        build_conn(:get, "/about")
        |> call_plug(endpoint: PhoenixPrerenderWeb.Endpoint)

      # Serves the page but no regeneration triggered
      assert conn.halted
      assert conn.status == 200
    end

    test "does not trigger regeneration without endpoint" do
      write_prerendered("/about", "<html>About</html>")
      file_path = PhoenixPrerender.Path.full_output_path("/about", @output_path, :dir_index)
      File.touch!(file_path, {{2020, 1, 1}, {0, 0, 0}})

      conn =
        build_conn(:get, "/about")
        |> call_plug()

      # Serves the page, no crash even without endpoint
      assert conn.halted
      assert conn.status == 200
    end
  end

  describe "Accept-Encoding negotiation" do
    test "serves compressed file when Accept-Encoding: gzip and .gz file exists" do
      write_prerendered("/about", "<html>About</html>")
      # Write the .gz variant
      file_path = PhoenixPrerender.Path.full_output_path("/about", @output_path, :dir_index)
      File.write!(file_path <> ".gz", :zlib.gzip("<html>About</html>"))

      conn =
        build_conn(:get, "/about")
        |> Plug.Conn.put_req_header("accept-encoding", "gzip, deflate")
        |> call_plug()

      assert conn.halted
      assert conn.status == 200
      assert get_resp_header(conn, "content-encoding") == ["gzip"]
      assert get_resp_header(conn, "vary") == ["accept-encoding"]
    end

    test "serves compressed file when Accept-Encoding: br and .br file exists" do
      write_prerendered("/about", "<html>About</html>")
      file_path = PhoenixPrerender.Path.full_output_path("/about", @output_path, :dir_index)
      File.write!(file_path <> ".br", "fake-brotli-content")

      conn =
        build_conn(:get, "/about")
        |> Plug.Conn.put_req_header("accept-encoding", "br, gzip")
        |> call_plug()

      assert conn.halted
      assert conn.status == 200
      assert get_resp_header(conn, "content-encoding") == ["br"]
      assert get_resp_header(conn, "vary") == ["accept-encoding"]
    end

    test "prefers br over gzip when both available" do
      write_prerendered("/about", "<html>About</html>")
      file_path = PhoenixPrerender.Path.full_output_path("/about", @output_path, :dir_index)
      File.write!(file_path <> ".gz", :zlib.gzip("<html>About</html>"))
      File.write!(file_path <> ".br", "fake-brotli-content")

      conn =
        build_conn(:get, "/about")
        |> Plug.Conn.put_req_header("accept-encoding", "gzip, br")
        |> call_plug()

      assert conn.halted
      assert get_resp_header(conn, "content-encoding") == ["br"]
    end

    test "serves uncompressed when no compressed file exists" do
      write_prerendered("/about", "<html>About</html>")

      conn =
        build_conn(:get, "/about")
        |> Plug.Conn.put_req_header("accept-encoding", "gzip")
        |> call_plug()

      assert conn.halted
      assert conn.status == 200
      assert get_resp_header(conn, "content-encoding") == []
    end

    test "serves uncompressed when no Accept-Encoding header" do
      write_prerendered("/about", "<html>About</html>")

      conn =
        build_conn(:get, "/about")
        |> call_plug()

      assert conn.halted
      assert conn.status == 200
      assert get_resp_header(conn, "content-encoding") == []
    end
  end

  describe "strict_paths" do
    test "serves page when path is in manifest" do
      write_prerendered("/about", "<html>About</html>")

      write_manifest([
        %{
          path: "/about",
          file: "about/index.html",
          size: 20,
          checksum: "abc",
          generated_at: "2024-01-01T00:00:00Z"
        }
      ])

      conn =
        build_conn(:get, "/about")
        |> call_plug(strict_paths: true)

      assert conn.halted
      assert conn.status == 200
    end

    test "rejects page when path is not in manifest" do
      write_prerendered("/secret", "<html>Secret</html>")

      write_manifest([
        %{
          path: "/about",
          file: "about/index.html",
          size: 20,
          checksum: "abc",
          generated_at: "2024-01-01T00:00:00Z"
        }
      ])

      conn =
        build_conn(:get, "/secret")
        |> call_plug(strict_paths: true)

      refute conn.halted
    end

    test "rejects all paths when no manifest exists" do
      write_prerendered("/about", "<html>About</html>")

      conn =
        build_conn(:get, "/about")
        |> call_plug(strict_paths: true)

      refute conn.halted
    end

    test "serves any file when strict_paths is false" do
      write_prerendered("/anything", "<html>Anything</html>")

      conn =
        build_conn(:get, "/anything")
        |> call_plug(strict_paths: false)

      assert conn.halted
      assert conn.status == 200
    end
  end
end
