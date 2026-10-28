defmodule PulseWeb.PageControllerTest do
  use PulseWeb.ConnCase

  test "GET / renders the locations list", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "What's happening in Lusaka"
  end
end
