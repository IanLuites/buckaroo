defmodule Buckaroo.Router do
  @moduledoc ~S"""
  An extension to `Plug.Router` now also supporting `websocket`.
  """

  @doc false
  defmacro __using__(opts) do
    quote location: :keep do
      use Plug.Router, unquote(opts)
      import Buckaroo.Router, only: [sse: 2, websocket: 2]
      @before_compile Buckaroo.Router
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      import Buckaroo.Router, only: []
    end
  end

  @doc ~S"""
  Dispatches to the websocket.

  See `Plug.Router.match/3` for more examples.

  ## Example

  ```
  websocket "/ws", connect: ExampleSocket
  ```
  """
  defmacro websocket(expr, opts) do
    method = :websocket
    {path, guards} = extract_path_and_guards(expr)
    body = quote do: Plug.Conn.put_private(var!(conn), :websocket, unquote(opts[:connect]))
    options = Keyword.delete(opts, :connect)

    quote bind_quoted: [
            method: method,
            path: path,
            options: options,
            guards: Macro.escape(guards, unquote: true),
            body: Macro.escape(body, unquote: true)
          ] do
      route = Plug.Router.__route__(method, path, guards, options)
      {conn, method, match, params, host, guards, private, assigns} = route

      defp do_match(unquote(conn), unquote(method), unquote(match), unquote(host))
           when unquote(guards) do
        unquote(private)
        unquote(assigns)

        merge_params = fn
          %Plug.Conn.Unfetched{} -> unquote({:%{}, [], params})
          fetched -> Map.merge(fetched, unquote({:%{}, [], params}))
        end

        conn = update_in(unquote(conn).params, merge_params)
        conn = update_in(conn.path_params, merge_params)

        Plug.Router.__put_route__(conn, unquote(path), fn var!(conn) -> unquote(body) end)
      end
    end
  end

  @doc ~S"""
  Dispatches to the event source.

  Server-Sent Events (SSE) is a server push technology enabling a client to receive automatic updates from a server via HTTP connection.

  See `Plug.Router.match/3` for more examples.

  ## Example

  ```
  sse "/eventsource", source: ExampleEventSource
  ```
  """
  defmacro sse(expr, opts) do
    method = :get
    {path, guards} = extract_path_and_guards(expr)

    body = quote do: Plug.Conn.put_private(var!(conn), :websocket, {:sse, unquote(opts[:source])})
    options = Keyword.delete(opts, :source)

    quote bind_quoted: [
            method: method,
            path: path,
            options: options,
            guards: Macro.escape(guards, unquote: true),
            body: Macro.escape(body, unquote: true)
          ] do
      route = Plug.Router.__route__(method, path, guards, options)
      {conn, method, match, params, host, guards, private, assigns} = route

      defp do_match(unquote(conn), unquote(method), unquote(match), unquote(host))
           when unquote(guards) do
        unquote(private)
        unquote(assigns)

        merge_params = fn
          %Plug.Conn.Unfetched{} -> unquote({:%{}, [], params})
          fetched -> Map.merge(fetched, unquote({:%{}, [], params}))
        end

        conn = update_in(unquote(conn).params, merge_params)
        conn = update_in(conn.path_params, merge_params)

        Plug.Router.__put_route__(conn, unquote(path), fn var!(conn), _ -> unquote(body) end)
      end
    end
  end

  # Extract the path and guards from the path.
  defp extract_path_and_guards({:when, _, [path, guards]}), do: {extract_path(path), guards}
  defp extract_path_and_guards(path), do: {extract_path(path), true}

  defp extract_path({:_, _, var}) when is_atom(var), do: "/*_path"
  defp extract_path(path), do: path
end
