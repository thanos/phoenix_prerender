defmodule DemoWeb.DocsControllerTest do
  use DemoWeb.ConnCase

  test "GET /docs renders docs index" do
    conn = get(build_conn(), ~p"/docs")
    assert html_response(conn, 200) =~ "Documentation"
  end

  test "GET /docs/getting-started renders nested doc" do
    conn = get(build_conn(), ~p"/docs/getting-started")
    assert html_response(conn, 200) =~ "Getting Started"
  end

  test "GET /docs/terms renders terms" do
    conn = get(build_conn(), ~p"/docs/terms")
    assert html_response(conn, 200) =~ "Prerendered under the /docs scope. Generated file:"
  end
end
