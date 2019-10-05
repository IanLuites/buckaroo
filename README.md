# Buckaroo

Simple `:cowboy` (v2) webserver with support for websockets.

## Quick Setup

```elixir
defmodule EchoSocket do
  use Buckaroo.Socket

  @impl Buckaroo.Socket
  def handle(frame, state), do: {:reply, frame, state}
end

defmodule TimeEventSource do
  use Buckaroo.EventSource

  @impl Buckaroo.EventSource
  def init(_conn, _opts), do: {:ok, :timer.send_interval(1_000, :time)}

  @impl Buckaroo.EventSource
  def info(:time, state),
    do: {:reply, %{event: "time", data: :os.system_time()}, state}

  def info(_message, state), do: {:ok, state}
end

defmodule MyRouter do
  use Buckaroo.Router

  plug :match
  plug :dispatch

  websocket "/echo", connect: EchoSocket
  sse "/sse/time", source: TimeEventSource

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

with SSE it is now possible to subscribe to these time events
in the browser with the following JavaScript:
```javascript
const es = new EventSource('/sse/time');

es.addEventListener('time', event => {
  console.log('system time', event.data);
});
```

## Installation

The package can be installed
by adding `buckaroo` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:buckaroo, "~> 0.2.0"}
  ]
end
```

The docs can be found at [https://hexdocs.pm/buckaroo](https://hexdocs.pm/buckaroo).
