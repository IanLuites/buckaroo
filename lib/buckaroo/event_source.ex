defmodule Buckaroo.EventSource do
  @moduledoc ~S"""
  A simple SSE implementation.
  """

  @typedoc ~S"""
  SSE event.
  """
  @type event ::
          %{
            required(:data) => binary,
            optional(:id) => binary,
            optional(:type) => binary,
            optional(:retry) => pos_integer
          }
          | binary

  @typedoc ~S"""
  SSE callback result.
  """
  @type result(state) ::
          {:ok, state}
          | {:ok, state, :hibernate}
          | {:reply, event | [event], state}
          | {:reply, event | [event], state, :hibernate}
          | {:stop, state}

  @doc ~S"""
  Initialize the SSE.

  Passes the connection and the given state.
  """
  @callback init(conn :: Plug.Conn.t(), state :: state) :: result(state) when state: any

  @doc ~S"""
  Incoming process messages.
  """
  @callback info(any, state) :: result(state) when state: any

  @doc ~S"""
  SSE termination.
  """
  @callback terminate(reason :: any, req :: map, state) :: :ok when state: any

  @doc false
  defmacro __using__(_opts \\ []) do
    quote do
      @behaviour Buckaroo.EventSource

      @impl Buckaroo.EventSource
      def init(_conn, state), do: {:ok, state}

      @impl Buckaroo.EventSource
      def info(_message, state), do: {:ok, state}

      @impl Buckaroo.EventSource
      def terminate(_, _, _), do: :ok

      defoverridable init: 2, info: 2, terminate: 3
    end
  end
end
