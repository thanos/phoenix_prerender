defmodule DemoWeb.PageControllerTest do
  use DemoWeb.ConnCase

  test "GET / renders landing page" do
    conn = get(build_conn(), ~p"/")
    assert html_response(conn, 200) =~ "Static Prerendering"
  end

  test "GET /about renders prerendered about page" do
    conn = get(build_conn(), ~p"/about")
    assert html_response(conn, 200) =~ "About PhoenixPrerender"
  end

  test "GET /features renders prerendered features page" do
    conn = get(build_conn(), ~p"/features")
    assert html_response(conn, 200) =~ "Features"
  end

  test "GET /contact renders dynamic contact page" do
    conn = get(build_conn(), ~p"/contact")
    assert html_response(conn, 200) =~ "Contact"
  end

  test "GET /dashboard renders dynamic dashboard page" do
    conn = get(build_conn(), ~p"/dashboard")
    assert html_response(conn, 200) =~ "Dashboard"
  end
end
