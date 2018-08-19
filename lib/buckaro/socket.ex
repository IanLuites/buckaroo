defmodule Buckaro.Socket do
  @moduledoc ~S"""
  A simple websocket implementation.
  """

  @typedoc ~S"""
  Websocket frames.

  Note that there is no need to send pong frames back as Cowboy does it automatically for you.
  """
  @type frame :: :ping | :pong | {:text | :binary | :ping | :pong, binary()}

  @typedoc ~S"""
  Websocket callback result.
  """
  @type result(state) ::
          {:ok, state}
          | {:ok, state, :hibernate}
          | {:reply, frame | [frame], state}
          | {:reply, frame | [frame], state, :hibernate}
          | {:stop, state}

  @doc ~S"""
  Initialize the websocket.

  Passes the connection and the given state.
  """
  @callback init(conn :: Plug.Conn.t(), state :: state) :: result(state) when state: any

  @doc ~S"""
  Incoming frames.
  """
  @callback handle(frame, state) :: result(state) when state: any

  @doc ~S"""
  Incoming process messages.
  """
  @callback info(any, state) :: result(state) when state: any

  @doc ~S"""
  Websocket termination.
  """
  @callback terminate(reason :: any, req :: map, state) :: :ok when state: any

  @doc false
  defmacro __using__(_opts \\ []) do
    quote do
      @behaviour Buckaro.Socket

      @impl Buckaro.Socket
      def init(_conn, state), do: {:ok, state}

      @impl Buckaro.Socket
      def handle(_frame, state), do: {:ok, state}

      @impl Buckaro.Socket
      def info(_message, state), do: {:ok, state}

      @impl Buckaro.Socket
      def terminate(_, _, _), do: :ok

      defoverridable init: 2, handle: 2, info: 2, terminate: 3
    end
  end
end
