defmodule Hirehound.Repo do
  use Ecto.Repo,
    otp_app: :hirehound,
    adapter: Ecto.Adapters.Postgres
end
