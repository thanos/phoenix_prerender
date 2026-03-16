# Benchmark: Prerendered (cache) vs Prerendered (disk) vs Dynamic rendering
#
# Run with: mix run bench/plug_serving_bench.exs
#
# Compares serving the same /about page through three paths:
#   1. ETS cache hit  — PhoenixPrerender.Plug serves from PageCache
#   2. Disk hit       — PhoenixPrerender.Plug serves from prerendered file
#   3. Dynamic render — Full Phoenix pipeline (router → controller → template)

alias PhoenixPrerender.PageCache
alias PhoenixPrerender.Plug, as: PrerenderPlug

# Suppress Phoenix request logs during benchmarking
Logger.configure(level: :warning)

IO.puts("\n=== PhoenixPrerender Benchmark ===")
IO.puts("Comparing the SAME /about page served three different ways\n")

# -- Setup -----------------------------------------------------------------

# Start PageCache if not already running
case PageCache.start_link() do
  {:ok, _pid} -> IO.puts("  [setup] Started PageCache")
  {:error, {:already_started, _}} -> IO.puts("  [setup] PageCache already running")
end

# Generate the prerendered /about page to disk
output_path = Elixir.Path.join([File.cwd!(), "priv", "static", "prerendered"])
File.mkdir_p!(output_path)

{:ok, html} = PhoenixPrerender.Renderer.render(DemoWeb.Endpoint, "/about")

# Write /about to disk (for cache scenario)
file_path = PhoenixPrerender.Path.full_output_path("/about", output_path, :dir_index)
file_path |> Elixir.Path.dirname() |> File.mkdir_p!()
File.write!(file_path, html)

# Write /about-disk to disk (identical content, used for disk-only scenario)
disk_file_path = PhoenixPrerender.Path.full_output_path("/about-disk", output_path, :dir_index)
disk_file_path |> Elixir.Path.dirname() |> File.mkdir_p!()
File.write!(disk_file_path, html)

byte_size = byte_size(html)
IO.puts("  [setup] Page size: #{byte_size} bytes (#{Float.round(byte_size / 1024, 1)} KB)")
IO.puts("  [setup] Disk file: #{file_path}")

# Warm the ETS cache for /about
PageCache.put("/about", html)
IO.puts("  [setup] ETS cache: warmed")

# Build plug opts (shared across cache and disk scenarios)
plug_opts =
  PrerenderPlug.init(
    output_path: output_path,
    enabled: true,
    strict_paths: false,
    cache_control: "public, max-age=300"
  )

IO.puts("")

# -- Benchmark -------------------------------------------------------------

Benchee.run(
  %{
    "1. prerendered (ETS cache)" => {
      fn _input ->
        Phoenix.ConnTest.build_conn(:get, "/about")
        |> PrerenderPlug.call(plug_opts)
      end,
      before_each: fn _input ->
        PageCache.put("/about", html)
        :ok
      end
    },
    "2. prerendered (disk read)" => {
      fn _input ->
        # /about-disk exists on disk but is never cached
        Phoenix.ConnTest.build_conn(:get, "/about-disk")
        |> PrerenderPlug.call(plug_opts)
      end,
      before_each: fn _input ->
        PageCache.delete("/about-disk")
        :ok
      end
    },
    "3. dynamic (full Phoenix pipeline)" => fn ->
      Phoenix.ConnTest.build_conn(:get, "/about")
      |> Plug.Conn.put_req_header("accept", "text/html")
      |> Phoenix.ConnTest.dispatch(DemoWeb.Endpoint, :get, "/about")
    end
  },
  time: 5,
  warmup: 2,
  memory_time: 2,
  reduction_time: 2,
  pre_check: true,
  formatters: [Benchee.Formatters.Console]
)

# -- Cleanup ----------------------------------------------------------------

File.rm_rf!(Elixir.Path.join(output_path, "about-disk"))
IO.puts("\n  [cleanup] Removed temporary about-disk files")
