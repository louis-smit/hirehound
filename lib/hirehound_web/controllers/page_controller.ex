defmodule HirehoundWeb.PageController do
  use HirehoundWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
