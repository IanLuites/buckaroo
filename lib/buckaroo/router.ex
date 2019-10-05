defmodule Buckaroo.Router do
  @moduledoc ~S"""
  An extension to `Plug.Router` now also supporting `websocket`.
  """

  @doc false
  defmacro __using__(opts) do
    quote location: :keep do
      use Plug.Router, unquote(opts)
      import Buckaroo.Router, only: [sse: 2, websocket: 2]
      Module.register_attribute(__MODULE__, :plug_forwards, accumulate: true)
      @on_definition {Buckaroo.Router, :on_def}
      @before_compile Buckaroo.Router
      @has_sse_route false
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      @doc false
      @spec __sse__ :: boolean
      if @has_sse_route do
        def __sse__, do: true
      else
        def __sse__ do
          Enum.any?(@plug_forwards, fn plug ->
            {:__sse__, 0} in plug.__info__(:functions) and plug.__sse__()
          end)
        end
      end

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

      @has_sse_route true
    end
  end

  @doc false
  @spec on_def(term, :def | :defp, atom, term, term, term) :: term
  # credo:disable-for-next-line
  def on_def(env, :defp, :do_match, [{:conn, _, Plug.Router}, _method, _path, _], _guards, _body) do
    if forward = Module.get_attribute(env.module, :plug_forward_target) do
      unless forward in Module.get_attribute(env.module, :plug_forwards) do
        Module.put_attribute(env.module, :plug_forwards, forward)
      end
    end
  end

  # credo:disable-for-next-line
  def on_def(_env, _type, _name, _args, _guards, _body), do: :ignore

  # Extract the path and guards from the path.
  defp extract_path_and_guards({:when, _, [path, guards]}), do: {extract_path(path), guards}
  defp extract_path_and_guards(path), do: {extract_path(path), true}

  defp extract_path({:_, _, var}) when is_atom(var), do: "/*_path"
  defp extract_path(path), do: path
end
