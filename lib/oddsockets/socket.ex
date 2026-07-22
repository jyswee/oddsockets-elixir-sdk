defmodule OddSockets.Socket do
  @moduledoc """
  Low-level Socket.IO (Engine.IO v4) transport over a WebSocket.

  The OddSockets worker speaks Socket.IO, so a plain WebSocket carrying raw JSON
  cannot complete its handshake. This module implements the Engine.IO v4 framing
  by hand on top of `WebSockex`:

    * Engine.IO `OPEN` (`0{...}`)  -> reply Socket.IO `CONNECT` (`40{auth}`),
      putting `apiKey`/`userId` into `socket.handshake.auth` on the server.
    * Engine.IO `PING` (`2`)       -> reply Engine.IO `PONG` (`3`).
    * Socket.IO `CONNECT` ack (`40{sid}`) -> notify the owner it is connected.
    * Socket.IO `EVENT` (`42["event", payload]`) -> forward `{event, payload}`.
    * Socket.IO `CONNECT_ERROR` (`44{...}`) -> notify the owner of failure.

  All decoded frames are delivered to the owner process as plain messages; this
  module holds no application state beyond the credentials and the owner pid.
  """

  use WebSockex
  require Logger

  @doc """
  Open a Socket.IO connection to `url`.

  `opts` must contain `:owner` (pid to receive decoded frames), `:api_key`, and
  `:user_id`. The socket is started unlinked so the owner controls its lifecycle
  via a monitor.
  """
  @spec start(String.t(), map()) :: {:ok, pid()} | {:error, term()}
  def start(url, opts) do
    WebSockex.start(url, __MODULE__, opts)
  end

  @doc """
  Send an already-framed Socket.IO packet (e.g. `42["subscribe", %{...}]`).
  """
  @spec push(pid(), String.t()) :: :ok | {:error, term()}
  def push(socket, frame) do
    WebSockex.send_frame(socket, {:text, frame})
  end

  @doc """
  Close the connection.
  """
  @spec close(pid()) :: :ok
  def close(socket) do
    WebSockex.cast(socket, :close)
  end

  ## WebSockex callbacks

  @impl true
  def handle_frame({:text, msg}, state) do
    cond do
      String.starts_with?(msg, "0") ->
        # Engine.IO OPEN -> Socket.IO CONNECT carrying auth credentials.
        auth = Jason.encode!(%{"apiKey" => state.api_key, "userId" => state.user_id})
        {:reply, {:text, "40" <> auth}, state}

      msg == "2" ->
        # Engine.IO PING -> PONG.
        {:reply, {:text, "3"}, state}

      msg == "3" ->
        # Engine.IO PONG (reply to a ping we sent); nothing to do.
        {:ok, state}

      String.starts_with?(msg, "40") ->
        send(state.owner, {:socket_connected, self()})
        {:ok, state}

      String.starts_with?(msg, "44") ->
        send(state.owner, {:socket_error, strip(msg, 2)})
        {:ok, state}

      String.starts_with?(msg, "42") ->
        case Jason.decode(strip(msg, 2)) do
          {:ok, [event, payload]} ->
            send(state.owner, {:socket_event, event, payload})

          {:ok, [event]} ->
            send(state.owner, {:socket_event, event, %{}})

          _ ->
            :ok
        end

        {:ok, state}

      true ->
        {:ok, state}
    end
  end

  def handle_frame(_frame, state), do: {:ok, state}

  @impl true
  def handle_cast(:close, state) do
    {:close, state}
  end

  def handle_cast(_msg, state), do: {:ok, state}

  @impl true
  def handle_disconnect(_reason, state) do
    send(state.owner, {:socket_closed, self()})
    {:ok, state}
  end

  # binary_part-based prefix strip (avoids String.slice range-step churn).
  defp strip(binary, n), do: binary_part(binary, n, byte_size(binary) - n)
end
