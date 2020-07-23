defmodule Buckaroo do
  @moduledoc ~S"""
  Simple `:cowboy` (v2) webserver with support for websockets.
  """
  alias Plug.Cowboy
  require Logger

  @doc ~S"""
  Setup a simple webserver handling HTTP requests including websockets.
  """
  @spec child_spec(Keyword.t()) :: Supervisor.child_spec()
  def child_spec(opts \\ []) do
    router =
      {plug, _} =
      {opts[:plug] || raise("Need to set plug: ... to the plug router."), opts[:opts] || []}

    if {:__sse__, 0} in plug.__info__(:functions) and plug.__sse__() do
      p = opts[:protocol_options] || []

      unless p[:idle_timeout] == :infinity do
        Logger.warn(fn ->
          """
          Buckaroo: serving SSE events, but `:idle_timeout` is not set to `:infinity`.

            This causes SSE EventSources to disconnect after the timeout passes.

            Please pass `protocol_options: [idle_timeout: :infinity]`
            to prevent disconnect after idle timeout.

            Example:

              Buckaroo.child_spec(plug: MyRouter, protocol_options: [idle_timeout: :infinity])
          """
        end)
      end
    end

    socket = if s = opts[:socket], do: {s, opts[:socket_opts] || opts[:opts] || []}

    options =
      [
        port: 3000,
        compress: true,
        dispatch: [{:_, [{:_, __MODULE__, {socket || router, router}}]}]
      ]
      |> Keyword.merge(Keyword.drop(opts, ~w(socket plug opts)a))
      |> Keyword.update!(:port, &if(is_binary(&1), do: String.to_integer(&1), else: &1))

    Cowboy.child_spec([scheme: :http, plug: elem(router, 0)] ++ options)
  end

  ### Handler ###
  @connection Plug.Cowboy.Conn
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

        {:sse, {socket, opts}} ->
          sse_init(conn, socket, opts)

        {:sse, socket} ->
          sse_init(conn, socket)

        {socket, opts} ->
          {:cowboy_websocket, req, {socket, {conn, opts}}}

        socket ->
          {:cowboy_websocket, req, {socket, {conn, []}}}
      end
    catch
      kind, reason ->
        exit_on_error(kind, reason, __STACKTRACE__, {plug, :call, [conn, opts]})
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

  defp exit_on_error(
         :error,
         %Plug.Conn.WrapperError{kind: kind, reason: reason, stack: stack},
         _stack,
         call
       ) do
    exit_on_error(kind, reason, stack, call)
  end

  defp exit_on_error(:error, value, stack, call) do
    exception = Exception.normalize(:error, value, stack)
    :erlang.raise(:exit, {{exception, stack}, call}, [])
  end

  defp exit_on_error(:throw, value, stack, call) do
    :erlang.raise(:exit, {{{:nocatch, value}, stack}, call}, [])
  end

  defp exit_on_error(:exit, value, _stack, call) do
    :erlang.raise(:exit, {value, call}, [])
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

  # Note: terminate overlaps with loop handler (SSE) terminate
  @impl :cowboy_websocket
  def terminate(reason, req, state)

  def terminate(reason, req, {socket, state}) when is_atom(socket) do
    if :erlang.function_exported(socket, :terminate, 3),
      do: socket.terminate(reason, req, state),
      else: :ok
  end

  def terminate(_, _, _), do: :ok

  @spec result(tuple, module) :: tuple
  defp result({:stop, state}, socket), do: {:stop, {socket, state}}
  defp result({:ok, state}, socket), do: {:ok, {socket, state}}
  defp result({:ok, state, :hibernate}, socket), do: {:ok, {socket, state}, :hibernate}
  defp result({:reply, frame, state}, socket), do: {:reply, frame, {socket, state}}

  defp result({:reply, frame, state, :hibernate}, socket),
    do: {:reply, frame, {socket, state}, :hibernate}

  ## Loop Handler

  @spec sse_init(term, module, term) :: tuple
  defp sse_init(c, handler, opts \\ []) do
    {:ok, conn, state} =
      case handler.init(c, opts) do
        {:ok, s} -> {:ok, c, s}
        {:ok, updated_c, s} -> {:ok, updated_c, s}
      end

    %{adapter: {_, req}} =
      conn
      |> Plug.Conn.put_resp_content_type("text/event-stream")
      |> Plug.Conn.put_resp_header("cache-control", "no-cache")
      |> Plug.Conn.send_chunked(200)

    {:cowboy_loop, req, {handler, state}, :hibernate}
  end

  @spec info(term, map, {module, term}) :: tuple
  def info(:eof, req, s = {handler, state}) do
    handler.terminate(:eof, req, state)
    {:stop, req, {handler, s}}
  end

  def info(msg, req, {handler, state}) do
    case handler.info(msg, state) do
      {:ok, s} -> {:ok, req, {handler, s}}
      {:ok, s, :hibernate} -> {:ok, req, {handler, s}, :hibernate}
      {:reply, events, s} -> {:ok, send_events(req, events), {handler, s}}
      {:reply, events, s, :hibernate} -> {:ok, send_events(req, events), {handler, s}, :hibernate}
      {:stop, s} -> {:stop, req, {handler, s}}
    end
  end

  @spec send_events(map, [map] | map) :: map
  defp send_events(req, events) when is_list(events),
    do: Enum.reduce(events, req, &send_events(&2, &1))

  defp send_events(req, event) do
    :cowboy_req.stream_body(sse_event(event), :nofin, req)
    req
  end

  defp sse_event(%{id: id, event: event, retry: retry, data: data}),
    do: "id: #{id}\nevent: #{event}\nretry: #{retry}\ndata: #{data}\n\n"

  defp sse_event(%{id: id, event: event, data: data}),
    do: "id: #{id}\nevent: #{event}\ndata: #{data}\n\n"

  defp sse_event(%{event: event, retry: retry, data: data}),
    do: "event: #{event}\nretry: #{retry}\ndata: #{data}\n\n"

  defp sse_event(%{id: id, retry: retry, data: data}),
    do: "id: #{id}\nretry: #{retry}\ndata: #{data}\n\n"

  defp sse_event(%{id: id, data: data}), do: "id: #{id}\ndata: #{data}\n\n"
  defp sse_event(%{event: event, data: data}), do: "event: #{event}\ndata: #{data}\n\n"
  defp sse_event(%{retry: retry, data: data}), do: "retry: #{retry}\ndata: #{data}\n\n"
  defp sse_event(%{data: data}), do: "data: #{data}\n\n"
  defp sse_event(data), do: "data: #{data}\n\n"
end
