# Buckaroo

Simple `:cowboy` (v2) webserver with support for websockets.

## Quick Setup

```elixir
defmodule EchoSocket do
  use Buckaroo.Socket

  @impl Buckaroo.Socket
  def handle(frame, state), do: {:reply, frame, state}
end

defmodule MyRouter do
  use Buckaroo.Router

  plug :match
  plug :dispatch

  websocket "/echo", connect: EchoSocket

  get "/" do
    Plug.Conn.send_resp(conn, 200, "Welcome")
  end
end

defmodule MyApp do
  use Application

  def start(_type, _args) do
    children = [Buckaroo.child_spec(plug: MyRouter)]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

## Installation

Thee package can be installed
by adding `buckaroo` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:buckaroo, "~> 0.1.0"}
  ]
end
```

The docs can be found at [https://hexdocs.pm/buckaroo](https://hexdocs.pm/buckaroo).
