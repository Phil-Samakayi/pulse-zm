defmodule PulseWeb.PageControllerTest do
  use PulseWeb.ConnCase

  test "GET / renders the locations list", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Pulse — Zambia cost-of-living tracker"
  end
end
