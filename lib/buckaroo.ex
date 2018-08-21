defmodule Buckaroo do
  @moduledoc ~S"""
  Simple `:cowboy` (v2) webserver with support for websockets.
  """
  alias Plug.Adapters.Cowboy2

  @doc ~S"""
  Setup a simple webserver handling HTTP requests including websockets.
  """
  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    router =
      {opts[:plug] || raise("Need to set plug: ... to the plug router."), opts[:opts] || []}

    socket = if s = opts[:socket], do: {s, opts[:socket_opts] || opts[:opts] || []}

    options =
      Keyword.merge(
        [port: 3000, dispatch: [{:_, [{:_, __MODULE__, {socket || router, router}}]}]],
        opts |> Keyword.delete(:socket) |> Keyword.delete(:plug) |> Keyword.delete(:opts)
      )

    {Cowboy2, scheme: :http, plug: elem(router, 0), options: options}
  end

  ### Handler ###
  @connection Plug.Adapters.Cowboy2.Conn
  @already_sent {:plug_conn, :sent}
  @behaviour :cowboy_websocket

  @impl :cowboy_websocket
  def init(req, {{socket, socket_opts}, {plug, plug_opts}}) do
    {conn, plug, opts} =
      if :cowboy_websocket.is_upgrade_request(req) do
        {%{@connection.conn(req) | method: "WEBSOCKET"}, socket, socket_opts}
      else
        {@connection.conn(req), plug, plug_opts}
      end

    try do
      conn = plug.call(conn, opts)

      case Map.get(conn.private, :websocket) do
        nil ->
          %{adapter: {@connection, req}} = maybe_send(conn, plug)
          {:ok, req, {plug, opts}}

        {socket, opts} ->
          {:cowboy_websocket, req, {socket, {conn, opts}}}

        socket ->
          {:cowboy_websocket, req, {socket, {conn, []}}}
      end
    catch
      :error, value ->
        stack = System.stacktrace()
        exception = Exception.normalize(:error, value, stack)
        exit({{exception, stack}, {plug, :call, [conn, opts]}})

      :throw, value ->
        stack = System.stacktrace()
        exit({{{:nocatch, value}, stack}, {plug, :call, [conn, opts]}})

      :exit, value ->
        exit({value, {plug, :call, [conn, opts]}})
    after
      receive do
        @already_sent -> :ok
      after
        0 -> :ok
      end
    end
  end

  defp maybe_send(%Plug.Conn{state: :unset}, _plug), do: raise(Plug.Conn.NotSentError)
  defp maybe_send(%Plug.Conn{state: :set} = conn, _plug), do: Plug.Conn.send_resp(conn)
  defp maybe_send(%Plug.Conn{} = conn, _plug), do: conn

  defp maybe_send(other, plug) do
    raise "Cowboy2 adapter expected #{inspect(plug)} to return Plug.Conn but got: " <>
            inspect(other)
  end

  ### Handling Socket ###

  @impl :cowboy_websocket
  def websocket_init({socket, {conn, state}}), do: conn |> socket.init(state) |> result(socket)

  @impl :cowboy_websocket
  def websocket_handle(frame, {socket, state}),
    do: frame |> socket.handle(state) |> result(socket)

  @impl :cowboy_websocket
  def websocket_info(info, {socket, state}),
    do: info |> socket.info(state) |> result(socket)

  @impl :cowboy_websocket
  def terminate(reason, req, {socket, state}) do
    if :erlang.function_exported(socket, :terminate, 3),
      do: socket.terminate(reason, req, state),
      else: :ok
  end

  @spec result(tuple, module) :: tuple
  defp result({:stop, state}, socket), do: {:stop, {socket, state}}
  defp result({:ok, state}, socket), do: {:ok, {socket, state}}
  defp result({:ok, state, :hibernate}, socket), do: {:ok, {socket, state}, :hibernate}
  defp result({:reply, frame, state}, socket), do: {:reply, frame, {socket, state}}

  defp result({:reply, frame, state, :hibernate}, socket),
    do: {:reply, frame, {socket, state}, :hibernate}
end
