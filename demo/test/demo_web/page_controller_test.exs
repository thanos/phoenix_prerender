defmodule DemoWeb.PageControllerTest do
  use DemoWeb.ConnCase

  test "GET / renders home page" do
    conn = get(build_conn(), ~p"/")
    assert html_response(conn, 200) =~ "PhoenixPrerender Demo"
  end

  test "GET /about renders prerendered about page" do
    conn = get(build_conn(), ~p"/about")
    assert html_response(conn, 200) =~ "About"
  end

  test "GET /features renders prerendered features page" do
    conn = get(build_conn(), ~p"/features")
    assert html_response(conn, 200) =~ "Features"
  end

  test "GET /contact renders dynamic contact page" do
    conn = get(build_conn(), ~p"/contact")
    assert html_response(conn, 200) =~ "Contact"
  end
end
