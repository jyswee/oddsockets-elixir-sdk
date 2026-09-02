defmodule OddSockets do
  @moduledoc """
  OddSockets Elixir SDK

  Provides a simple interface to the OddSockets real-time messaging platform.
  Automatically handles manager discovery and Worker load balancing internally.

  ## Usage

      # Create a client
      {:ok, client} = OddSockets.start_link(api_key: "your-api-key")

      # Get a channel
      channel = OddSockets.channel(client, "my-channel")

      # Subscribe to messages
      :ok = OddSockets.Channel.subscribe(channel, fn message ->
        IO.inspect(message, label: "Received")
      end)

      # Publish a message
      {:ok, result} = OddSockets.Channel.publish(channel, %{text: "Hello World!"})

  """

  use GenServer
  require Logger

  alias OddSockets.{Channel, ManagerDiscovery, MessageSizeValidator, Types, Error}

  @type config :: %{
          api_key: String.t() | nil,
          token_provider: (-> String.t() | map()) | nil,
          token_refresh_lead_ms: non_neg_integer(),
          user_id: String.t() | nil,
          manager_url: String.t(),
          options: map()
        }

  @type state :: %{
          config: config(),
          socket: pid() | nil,
          socket_ref: reference() | nil,
          worker_url: String.t() | nil,
          worker_id: String.t() | nil,
          channels: %{String.t() => pid()},
          connection_state: atom(),
          reconnect_attempts: non_neg_integer(),
          max_reconnect_attempts: non_neg_integer(),
          reconnect_delay: non_neg_integer(),
          client_identifier: String.t(),
          session_info: map() | nil,
          subscribers: [pid()],
          pending: %{String.t() => GenServer.from()},
          listeners: %{String.t() => [function()]},
          connect_from: GenServer.from() | nil,
          connect_timer: reference() | nil,
          assignment: map() | nil,
          intentional_disconnect: boolean(),
          current_token: String.t() | nil,
          token_expires_at: non_neg_integer() | nil,
          token_refresh_timer: reference() | nil
        }

  @max_reconnect_attempts 5
  @initial_reconnect_delay 1000

  ## Public API

  @doc """
  Start an OddSockets client.

  ## Options

    * `:api_key` - Your OddSockets API key (required unless `:token_provider`
      is supplied)
    * `:token_provider` - Zero-arity function that mints a short-lived realtime
      token. When set, the client resolves a **fresh** token before every
      (re)connect, presents it on the manager/worker handshake in place of an
      API key, and silently refreshes it ahead of expiry. The function may
      return the token binary or a map with `:token`/"token" plus optional
      `:expires_at`/"expiresAt" (ISO-8601 or epoch) or `:exp`/"exp" (epoch
      seconds)
    * `:token_refresh_lead_ms` - How early (ms) to refresh the token ahead of
      its expiry (default: 120_000)
    * `:user_id` - User ID (defaults to API key's user)
    * `:manager_url` - Manager endpoint to use. Falls back to
      `config :oddsockets, manager_url: ...`, then `ODDSOCKETS_MANAGER_URL`,
      then the public endpoint. Whatever resolves is used verbatim; raises
      `ArgumentError` if it is not an absolute http(s) URL
    * `:options` - Additional connection options
    * `:auto_connect` - Whether to auto-connect (default: true)

  ## Examples

      {:ok, client} = OddSockets.start_link(api_key: "your-api-key")

      {:ok, client} = OddSockets.start_link(
        api_key: "your-api-key",
        user_id: "user123",
        auto_connect: false
      )

      # Point at a self-hosted or QA manager
      {:ok, client} = OddSockets.start_link(
        api_key: "your-api-key",
        manager_url: "https://manager.internal.example"
      )

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    config = build_config(opts)
    GenServer.start_link(__MODULE__, config, name: opts[:name])
  end

  @doc """
  Connect to the OddSockets platform.

  Handles the Manager → Worker assignment internally.
  """
  @spec connect(pid()) :: :ok | {:error, term()}
  def connect(client) do
    GenServer.call(client, :connect, 15_000)
  end

  @doc """
  Disconnect from the platform.
  """
  @spec disconnect(pid()) :: :ok
  def disconnect(client) do
    GenServer.call(client, :disconnect)
  end

  @doc """
  Get or create a channel.

  Returns a Channel process that can be used for pub/sub operations.
  """
  @spec channel(pid(), String.t()) :: pid()
  def channel(client, channel_name) when is_binary(channel_name) do
    GenServer.call(client, {:channel, channel_name})
  end

  @doc """
  Get current connection state.
  """
  @spec get_state(pid()) :: atom()
  def get_state(client) do
    GenServer.call(client, :get_state)
  end

  @doc """
  Get assigned worker information.
  """
  @spec get_worker_info(pid()) :: %{worker_id: String.t(), worker_url: String.t()} | nil
  def get_worker_info(client) do
    GenServer.call(client, :get_worker_info)
  end

  @doc """
  Get client identifier used for session stickiness.
  """
  @spec get_client_identifier(pid()) :: String.t()
  def get_client_identifier(client) do
    GenServer.call(client, :get_client_identifier)
  end

  @doc """
  Get session information.
  """
  @spec get_session_info(pid()) :: map() | nil
  def get_session_info(client) do
    GenServer.call(client, :get_session_info)
  end

  @doc """
  Publish multiple messages at once.

  ## Examples

      messages = [
        %{channel: "channel1", message: %{text: "Hello"}},
        %{channel: "channel2", message: %{text: "World"}, options: %{ttl: 300}}
      ]

      {:ok, results} = OddSockets.publish_bulk(client, messages)

  """
  @spec publish_bulk(pid(), [Types.bulk_message()]) :: {:ok, [Types.publish_result()]} | {:error, term()}
  def publish_bulk(client, messages) when is_list(messages) do
    GenServer.call(client, {:publish_bulk, messages}, 30_000)
  end

  @doc """
  Subscribe to client events.

  Events include: `:connecting`, `:connected`, `:disconnected`, `:error`, 
  `:reconnecting`, `:worker_assigned`, `:max_reconnect_attempts_reached`
  """
  @spec subscribe_events(pid()) :: :ok
  def subscribe_events(client) do
    GenServer.call(client, {:subscribe_events, self()})
  end

  @doc """
  Unsubscribe from client events.
  """
  @spec unsubscribe_events(pid()) :: :ok
  def unsubscribe_events(client) do
    GenServer.call(client, {:unsubscribe_events, self()})
  end

  @doc false
  # Sends a Socket.IO event and waits for the correlated worker response.
  #
  # `response_event` is the event the worker replies with (e.g. "subscribed"
  # for a "subscribe" request); the reply is matched on
  # `"<response_event>:<channel>"`. Used by `OddSockets.Channel`.
  @spec send_event(pid(), String.t(), String.t(), String.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def send_event(client, response_event, channel, event, payload) do
    GenServer.call(client, {:send_event, response_event, channel, event, payload}, 15_000)
  end

  @doc """
  Emit a fire-and-forget Socket.IO event to the worker.

  Used by `OddSockets.EnhancedFeatures` for enhanced (Slack-like) actions such
  as `start_typing`, `add_reaction`, `set_status`. The event is framed as a
  Socket.IO EVENT (`42["event", payload]`) and sent over the live connection.
  """
  @spec emit(pid(), String.t(), map()) :: :ok | {:error, term()}
  def emit(client, event, payload \\ %{}) do
    GenServer.call(client, {:emit, event, payload})
  end

  @doc """
  Register a one-shot listener for a worker broadcast event.

  The callback fires the next time `event` arrives from the worker and is then
  removed. Used by `OddSockets.EnhancedFeatures` to await a correlated response
  (e.g. `thread_data`, `message_reactions`). Enhanced broadcasts also surface on
  processes registered via `subscribe_events/1`.
  """
  @spec once(pid(), String.t(), (map() -> any())) :: :ok
  def once(client, event, callback) when is_function(callback, 1) do
    GenServer.call(client, {:once, event, callback})
  end

  ## GenServer Callbacks

  @impl true
  def init(config) do
    state = %{
      config: config,
      socket: nil,
      socket_ref: nil,
      worker_url: nil,
      worker_id: nil,
      channels: %{},
      connection_state: :disconnected,
      reconnect_attempts: 0,
      max_reconnect_attempts: @max_reconnect_attempts,
      reconnect_delay: @initial_reconnect_delay,
      client_identifier: generate_client_identifier(config),
      session_info: nil,
      subscribers: [],
      pending: %{},
      listeners: %{},
      connect_from: nil,
      connect_timer: nil,
      assignment: nil,
      intentional_disconnect: false,
      current_token: nil,
      token_expires_at: nil,
      token_refresh_timer: nil
    }

    # Auto-connect by default
    if Map.get(config, :auto_connect, true) do
      send(self(), :connect)
    end

    {:ok, state}
  end

  @impl true
  def handle_call(:connect, _from, %{connection_state: state} = s)
      when state in [:connecting, :connected] do
    {:reply, :ok, s}
  end

  def handle_call(:connect, from, state) do
    case start_connection(%{state | connect_from: from}) do
      {:ok, new_state} ->
        # Reply is deferred until the Socket.IO handshake completes.
        {:noreply, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, %{new_state | connect_from: nil}}
    end
  end

  def handle_call(:disconnect, _from, state) do
    new_state = do_disconnect(state)
    {:reply, :ok, new_state}
  end

  def handle_call({:send_event, response_event, channel, event, payload}, from, state) do
    if state.connection_state != :connected or is_nil(state.socket) do
      {:reply, {:error, :not_connected}, state}
    else
      key = "#{response_event}:#{channel}"
      frame = "42" <> Jason.encode!([event, prune_nils(payload)])

      case OddSockets.Socket.push(state.socket, frame) do
        :ok ->
          Process.send_after(self(), {:event_timeout, key}, 10_000)
          {:noreply, %{state | pending: Map.put(state.pending, key, from)}}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  def handle_call({:emit, event, payload}, _from, state) do
    if state.connection_state != :connected or is_nil(state.socket) do
      {:reply, {:error, :not_connected}, state}
    else
      frame = "42" <> Jason.encode!([event, prune_nils(payload)])

      case OddSockets.Socket.push(state.socket, frame) do
        :ok -> {:reply, :ok, state}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    end
  end

  def handle_call({:once, event, callback}, _from, state) do
    existing = Map.get(state.listeners, event, [])
    new_listeners = Map.put(state.listeners, event, existing ++ [callback])
    {:reply, :ok, %{state | listeners: new_listeners}}
  end

  def handle_call({:channel, channel_name}, _from, state) do
    case Map.get(state.channels, channel_name) do
      nil ->
        {:ok, channel_pid} = Channel.start_link(channel_name, self())
        new_channels = Map.put(state.channels, channel_name, channel_pid)
        new_state = %{state | channels: new_channels}
        {:reply, channel_pid, new_state}
      
      channel_pid ->
        {:reply, channel_pid, state}
    end
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state.connection_state, state}
  end

  def handle_call(:get_worker_info, _from, state) do
    case {state.worker_id, state.worker_url} do
      {nil, _} -> {:reply, nil, state}
      {_, nil} -> {:reply, nil, state}
      {worker_id, worker_url} ->
        info = %{worker_id: worker_id, worker_url: worker_url}
        {:reply, info, state}
    end
  end

  def handle_call(:get_client_identifier, _from, state) do
    {:reply, state.client_identifier, state}
  end

  def handle_call(:get_session_info, _from, state) do
    {:reply, state.session_info, state}
  end

  def handle_call({:publish_bulk, messages}, _from, state) do
    if state.connection_state != :connected do
      {:reply, {:error, :not_connected}, state}
    else
      results = Enum.map(messages, &publish_single_message(&1, state))
      {:reply, {:ok, results}, state}
    end
  end

  def handle_call({:subscribe_events, pid}, _from, state) do
    new_subscribers = [pid | state.subscribers] |> Enum.uniq()
    new_state = %{state | subscribers: new_subscribers}
    {:reply, :ok, new_state}
  end

  def handle_call({:unsubscribe_events, pid}, _from, state) do
    new_subscribers = List.delete(state.subscribers, pid)
    new_state = %{state | subscribers: new_subscribers}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:connect, %{connection_state: cs} = state)
      when cs in [:connecting, :connected] do
    {:noreply, state}
  end

  def handle_info(:connect, state) do
    case start_connection(state) do
      {:ok, new_state} ->
        {:noreply, new_state}

      {:error, _reason, new_state} ->
        {:noreply, schedule_reconnect(new_state)}
    end
  end

  def handle_info(:reconnect, state) do
    send(self(), :connect)
    {:noreply, state}
  end

  # Socket.IO handshake completed: the transport is live.
  def handle_info({:socket_connected, _socket}, state) do
    if state.connect_timer, do: Process.cancel_timer(state.connect_timer)

    new_state = %{
      state
      | connection_state: :connected,
        reconnect_attempts: 0,
        reconnect_delay: @initial_reconnect_delay,
        connect_timer: nil
    }

    broadcast_event(:connected, new_state)

    if state.assignment do
      broadcast_event(:worker_assigned, state.assignment, new_state)
    end

    if state.connect_from, do: GenServer.reply(state.connect_from, :ok)

    {:noreply, schedule_token_refresh(%{new_state | connect_from: nil})}
  end

  # Silent pre-expiry token refresh (token mode only).
  def handle_info(:token_refresh, state) do
    if token_mode?(state) do
      case resolve_token(state) do
        {:ok, new_state} ->
          broadcast_event(:token_refreshed, %{expires_at: new_state.token_expires_at}, new_state)
          {:noreply, schedule_token_refresh(%{new_state | token_refresh_timer: nil})}

        {:error, reason} ->
          Logger.warning("OddSockets token refresh failed: #{inspect(reason)}")
          broadcast_event(:error, {:token_refresh_failed, reason}, state)
          {:noreply, %{state | token_refresh_timer: nil}}
      end
    else
      {:noreply, state}
    end
  end

  # Socket.IO CONNECT_ERROR during the handshake.
  def handle_info({:socket_error, raw}, state) do
    if state.connect_timer, do: Process.cancel_timer(state.connect_timer)
    reason = {:connect_error, raw}
    broadcast_event(:error, reason, state)

    if state.connect_from, do: GenServer.reply(state.connect_from, {:error, reason})

    {:noreply, %{state | connection_state: :disconnected, connect_from: nil, connect_timer: nil}}
  end

  # A decoded Socket.IO event from the worker.
  def handle_info({:socket_event, event, payload}, state) do
    {:noreply, dispatch_worker_event(event, payload, state)}
  end

  def handle_info({:socket_closed, socket}, state) do
    if socket == state.socket and not state.intentional_disconnect do
      new_state = %{state | connection_state: :disconnected, socket: nil}
      broadcast_event(:disconnected, new_state)
      {:noreply, schedule_reconnect(new_state)}
    else
      {:noreply, state}
    end
  end

  def handle_info(:connect_timeout, state) do
    if state.connection_state == :connecting and state.connect_from do
      GenServer.reply(state.connect_from, {:error, :connect_timeout})

      if state.socket, do: OddSockets.Socket.close(state.socket)

      {:noreply, %{state | connection_state: :disconnected, connect_from: nil, connect_timer: nil, socket: nil}}
    else
      {:noreply, state}
    end
  end

  def handle_info({:event_timeout, key}, state) do
    case Map.pop(state.pending, key) do
      {nil, _} ->
        {:noreply, state}

      {from, rest} ->
        GenServer.reply(from, {:error, :timeout})
        {:noreply, %{state | pending: rest}}
    end
  end

  # Socket process went down.
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{socket_ref: ref} = state) do
    if state.intentional_disconnect do
      {:noreply, %{state | socket: nil, socket_ref: nil}}
    else
      new_state = %{state | connection_state: :disconnected, socket: nil, socket_ref: nil}
      broadcast_event(:disconnected, new_state)
      {:noreply, schedule_reconnect(new_state)}
    end
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove dead channel processes
    new_channels =
      state.channels
      |> Enum.reject(fn {_name, channel_pid} -> channel_pid == pid end)
      |> Map.new()

    {:noreply, %{state | channels: new_channels}}
  end

  ## Private Functions

  defp build_config(opts) do
    api_key = Keyword.get(opts, :api_key)
    token_provider = Keyword.get(opts, :token_provider)

    # A token_provider stands in for a static API key: game/app clients mint a
    # short-lived token instead of shipping a key, so an api_key is only
    # required when no provider is configured.
    if is_nil(api_key) and is_nil(token_provider) do
      raise ArgumentError, "either :api_key or :token_provider is required"
    end

    if token_provider != nil and not is_function(token_provider, 0) do
      raise ArgumentError, ":token_provider must be a zero-arity function"
    end

    # Resolved once, up front: a bad manager URL is a configuration mistake and
    # must stop the client from starting rather than reappear later disguised as
    # a connection failure - or, worse, be replaced by the public endpoint.
    manager_url = ManagerDiscovery.discover_manager_url!(Keyword.get(opts, :manager_url))

    %{
      api_key: api_key,
      token_provider: token_provider,
      token_refresh_lead_ms: Keyword.get(opts, :token_refresh_lead_ms, 120_000),
      user_id: Keyword.get(opts, :user_id),
      manager_url: manager_url,
      options: Keyword.get(opts, :options, %{}),
      auto_connect: Keyword.get(opts, :auto_connect, true)
    }
  end

  # Discovers a worker, opens the Socket.IO transport, and arms a handshake
  # timeout. The caller's reply (for an explicit `connect/1`) is deferred until
  # `{:socket_connected, _}` arrives.
  defp start_connection(state) do
    state = %{state | connection_state: :connecting, intentional_disconnect: false}
    broadcast_event(:connecting, state)

    # Step 0 (token mode): resolve a FRESH token before every (re)connect so
    # the manager and worker handshakes never present an expired credential.
    with {:ok, state} <- maybe_resolve_token(state),
         {:ok, assignment} <- get_worker_assignment(state),
         ws_url = build_ws_url(assignment.url),
         {:ok, socket} <-
           OddSockets.Socket.start(ws_url, %{
             owner: self(),
             api_key: state.config.api_key,
             token: state.current_token,
             user_id: state.config.user_id || state.client_identifier
           }) do
      ref = Process.monitor(socket)
      timer = Process.send_after(self(), :connect_timeout, 15_000)

      new_state = %{
        state
        | socket: socket,
          socket_ref: ref,
          worker_url: assignment.url,
          worker_id: assignment.worker_id,
          session_info: assignment.session,
          assignment: assignment,
          connect_timer: timer
      }

      {:ok, new_state}
    else
      {:error, reason} ->
        new_state = %{state | connection_state: :disconnected}
        broadcast_event(:error, reason, new_state)
        {:error, reason, new_state}
    end
  end

  # Converts an http(s) worker URL into a Socket.IO WebSocket endpoint.
  defp build_ws_url(url) do
    base =
      url
      |> String.replace_prefix("https://", "wss://")
      |> String.replace_prefix("http://", "ws://")
      |> String.trim_trailing("/")

    "#{base}/socket.io/?EIO=4&transport=websocket"
  end

  defp do_disconnect(state) do
    if state.socket do
      OddSockets.Socket.close(state.socket)
    end

    if state.token_refresh_timer, do: Process.cancel_timer(state.token_refresh_timer)

    # Fail any in-flight requests so callers do not hang.
    Enum.each(state.pending, fn {_key, from} ->
      GenServer.reply(from, {:error, :disconnected})
    end)

    new_state = %{
      state
      | connection_state: :disconnected,
        socket: nil,
        socket_ref: nil,
        worker_url: nil,
        worker_id: nil,
        pending: %{},
        intentional_disconnect: true,
        token_refresh_timer: nil
    }

    broadcast_event(:disconnected, new_state)
    new_state
  end

  defp get_worker_assignment(state) do
    # The configured manager is the only endpoint contacted: if it is down the
    # connection fails with that error rather than quietly landing elsewhere.
    manager_url = state.config.manager_url
    url = "#{manager_url}/api/cluster/select-worker"
    
    credential =
      if token_mode?(state),
        do: {"token", state.current_token},
        else: {"apiKey", state.config.api_key}

    params =
      Map.new([
        credential,
        {"userId", state.config.user_id || state.client_identifier},
        {"clientIdentifier", state.client_identifier}
      ])
    
    headers = [
      {"User-Agent", "OddSockets-Elixir-SDK/1.0.0"},
      {"Content-Type", "application/json"}
    ]
    
    case HTTPoison.get(url, headers, params: params, timeout: 10_000, recv_timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"url" => worker_url, "workerId" => worker_id} = response} ->
            assignment = %{
              url: worker_url,
              worker_id: worker_id,
              session: Map.get(response, "session"),
              client_identifier: state.client_identifier,
              manager_url: manager_url  # The manager actually used, for debugging
            }
            {:ok, assignment}
          
          {:error, _} ->
            {:error, :invalid_response}
        end
      
      {:ok, %HTTPoison.Response{status_code: status}} ->
        {:error, {:http_error, status}}
      
      {:error, %HTTPoison.Error{reason: reason}} ->
        if reason in [:econnrefused, :nxdomain] do
          {:error, :manager_offline}
        else
          {:error, reason}
        end
    end
  end

  # Routes a decoded worker event to the correct place: `message` envelopes go
  # to the owning channel; `error` fails an in-flight request; everything else
  # is a correlated response to a pending request.
  defp dispatch_worker_event("message", payload, state) do
    route_message(payload, state)
    state
  end

  defp dispatch_worker_event("error", payload, state) do
    case take_any_pending(state) do
      {nil, new_state} ->
        broadcast_event(:error, extract_error(payload), new_state)
        new_state

      {from, new_state} ->
        GenServer.reply(from, {:error, extract_error(payload)})
        new_state
    end
  end

  defp dispatch_worker_event("history", payload, state) do
    # The worker emits "history" both as the explicit get_history RESPONSE
    # (query:true) and as a fire-and-forget on-join snapshot (no query flag,
    # ~10 msgs). Only the query:true response may complete a pending get_history
    # waiter; the snapshot is delivered as a broadcast so it can't resolve
    # get_history with the wrong data. BUG-2026-0727-0012.
    if Map.get(payload, "query") == true do
      channel = Map.get(payload, "channel")
      key = "history:#{channel}"

      case Map.pop(state.pending, key) do
        {nil, _} ->
          deliver_broadcast("history", payload, state)

        {from, rest} ->
          GenServer.reply(from, {:ok, adapt_response("history", payload)})
          %{state | pending: rest}
      end
    else
      deliver_broadcast("history", payload, state)
    end
  end

  defp dispatch_worker_event(event, payload, state) do
    channel = Map.get(payload, "channel")
    key = "#{event}:#{channel}"

    case Map.pop(state.pending, key) do
      {nil, _} ->
        # Not a correlated channel response - treat as an enhanced (Slack-like)
        # broadcast: user_typing, reaction_added, thread_reply, notifications,
        # challenge_progress, leaderboard_rank_change, challenge_complete,
        # achievement_unlock, achievement_progress, challenge_invited,
        # challenge_reply_received, challenge_invite_cancelled,
        # etc. Fire any one-shot `once/3` listeners and surface it on the public
        # event stream for `subscribe_events/1` consumers.
        deliver_broadcast(event, payload, state)

      {from, rest} ->
        GenServer.reply(from, {:ok, adapt_response(event, payload)})
        %{state | pending: rest}
    end
  end

  # Delivers an enhanced broadcast to registered one-shot listeners and event
  # subscribers. Listeners for the event are invoked once and then removed.
  defp deliver_broadcast(event, payload, state) do
    {callbacks, remaining} = Map.pop(state.listeners, event, [])

    Enum.each(callbacks, fn callback ->
      try do
        callback.(payload)
      rescue
        e -> Logger.warning("OddSockets once/3 listener for #{event} raised: #{inspect(e)}")
      end
    end)

    broadcast_event(event, payload, state)
    %{state | listeners: remaining}
  end

  # Delivers a worker message envelope to the subscribing channel process.
  defp route_message(payload, state) do
    channel_name = Map.get(payload, "channel")

    case Map.get(state.channels, channel_name) do
      nil ->
        :ok

      channel_pid ->
        send(channel_pid, {:websocket_message, adapt_message(payload)})
    end
  end

  # Worker message envelope -> the map channels/callbacks expect.
  defp adapt_message(payload) do
    inner = Map.get(payload, "message")

    %{
      "type" => "message",
      "channel" => Map.get(payload, "channel"),
      "id" => Map.get(payload, "id"),
      "data" => inner,
      "message" => inner,
      "userId" => get_in(payload, ["publisher", "userId"]),
      "timestamp" => Map.get(payload, "timestamp"),
      "metadata" => Map.get(payload, "metadata")
    }
  end

  defp adapt_response("presence", payload) do
    occupants = Map.get(payload, "occupants", [])

    %{
      "channel" => Map.get(payload, "channel"),
      "count" => Map.get(payload, "occupancy", length(occupants)),
      "occupants" => occupants,
      "users" => occupants
    }
  end

  defp adapt_response("published", payload) do
    %{
      "channel" => Map.get(payload, "channel"),
      "message_id" => Map.get(payload, "messageId"),
      "messageId" => Map.get(payload, "messageId"),
      "timestamp" => Map.get(payload, "timestamp"),
      "subscriber_count" => Map.get(payload, "subscriberCount")
    }
  end

  defp adapt_response("history", payload) do
    %{
      "channel" => Map.get(payload, "channel"),
      "messages" => Map.get(payload, "messages", []),
      "count" => Map.get(payload, "count", 0)
    }
  end

  defp adapt_response(_event, payload), do: payload

  defp extract_error(%{"message" => message}), do: message
  defp extract_error(%{"type" => type}), do: type
  defp extract_error(other), do: inspect(other)

  # Pops an arbitrary pending waiter (worker error events carry no correlation
  # id, so the earliest in-flight request is failed).
  defp take_any_pending(state) do
    case Enum.take(state.pending, 1) do
      [{key, from}] -> {from, %{state | pending: Map.delete(state.pending, key)}}
      [] -> {nil, state}
    end
  end

  # Drops keys whose value is nil so the worker never receives JSON null where
  # it destructures with an object default (which would crash its handler).
  defp prune_nils(map) when is_map(map) and not is_struct(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn {k, v} -> {k, prune_nils(v)} end)
    |> Map.new()
  end

  defp prune_nils(value), do: value

  defp schedule_reconnect(state) do
    if state.reconnect_attempts < state.max_reconnect_attempts do
      new_state = %{state |
        connection_state: :reconnecting,
        reconnect_attempts: state.reconnect_attempts + 1
      }
      
      delay = min(state.reconnect_delay * :math.pow(2, new_state.reconnect_attempts - 1), 30_000)
      |> trunc()
      
      broadcast_event(:reconnecting, %{
        attempt: new_state.reconnect_attempts,
        max_attempts: state.max_reconnect_attempts,
        delay: delay
      }, new_state)
      
      Process.send_after(self(), :reconnect, delay)
      
      %{new_state | reconnect_delay: delay}
    else
      broadcast_event(:max_reconnect_attempts_reached, state)
      %{state | connection_state: :disconnected}
    end
  end

  defp publish_single_message(%{channel: channel_name, message: message} = msg, state) do
    try do
      MessageSizeValidator.validate_message_size(message)
      
      case Map.get(state.channels, channel_name) do
        nil ->
          %{success: false, error: "Channel not found"}
        
        channel_pid ->
          options = Map.get(msg, :options, %{})
          case Channel.publish(channel_pid, message, options) do
            {:ok, result} ->
              %{success: true, result: result}
            {:error, error} ->
              %{success: false, error: to_string(error)}
          end
      end
    rescue
      e in Error ->
        %{success: false, error: e.message}
    end
  end

  defp generate_client_identifier(config) do
    base_id = config.user_id || "default"
    # In token mode there is no api_key; seed the stickiness hash instead.
    api_key_hash = hash_string(config.api_key || "token-client")
    "#{api_key_hash}_#{base_id}"
  end

  ## Token-mode helpers (FEAT-0040)

  defp token_mode?(state), do: state.config[:token_provider] != nil

  defp maybe_resolve_token(state) do
    if token_mode?(state), do: resolve_token(state), else: {:ok, state}
  end

  # Calls the configured token_provider and stores the fresh token + expiry.
  defp resolve_token(state) do
    minted =
      try do
        {:ok, state.config.token_provider.()}
      rescue
        e -> {:error, {:token_provider_failed, Exception.message(e)}}
      end

    with {:ok, raw} <- minted,
         {token, expires_at} <- extract_token(raw),
         false <- token in [nil, ""] do
      expires_at = expires_at || expiry_from_jwt(token)
      {:ok, %{state | current_token: token, token_expires_at: expires_at}}
    else
      true -> {:error, :empty_token}
      {:error, reason} -> {:error, reason}
    end
  end

  # Accepts the token binary itself or a map (atom or string keys) with
  # token / expiresAt (ISO-8601 or epoch) / exp (epoch seconds).
  defp extract_token(token) when is_binary(token), do: {token, nil}

  defp extract_token(%{} = raw) do
    token = raw[:token] || raw["token"]
    expires_at = raw[:expires_at] || raw["expiresAt"] || raw[:expiresAt]
    exp = raw[:exp] || raw["exp"]

    ms =
      cond do
        is_integer(exp) -> exp * 1000
        is_number(expires_at) and expires_at < 1.0e12 -> trunc(expires_at * 1000)
        is_number(expires_at) -> trunc(expires_at)
        is_binary(expires_at) -> parse_iso_ms(expires_at)
        true -> nil
      end

    {token, ms}
  end

  defp extract_token(_), do: {nil, nil}

  defp parse_iso_ms(value) do
    case DateTime.from_iso8601(value) do
      {:ok, dt, _offset} -> DateTime.to_unix(dt, :millisecond)
      _ -> nil
    end
  end

  # Best-effort expiry from the JWT payload's exp claim (epoch seconds).
  defp expiry_from_jwt(token) do
    with [_, payload, _] <- String.split(token, "."),
         {:ok, json} <- Base.url_decode64(payload, padding: false),
         {:ok, %{"exp" => exp}} when is_integer(exp) <- Jason.decode(json) do
      exp * 1000
    else
      _ -> nil
    end
  end

  # Arms (or re-arms) the silent pre-expiry refresh timer.
  defp schedule_token_refresh(state) do
    if state.token_refresh_timer, do: Process.cancel_timer(state.token_refresh_timer)

    case {token_mode?(state), state.token_expires_at} do
      {true, expires_at} when is_integer(expires_at) ->
        delay = max(expires_at - System.system_time(:millisecond) - state.config.token_refresh_lead_ms, 0)
        %{state | token_refresh_timer: Process.send_after(self(), :token_refresh, delay)}

      _ ->
        %{state | token_refresh_timer: nil}
    end
  end

  defp hash_string(str) do
    :crypto.hash(:md5, str)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 8)
  end

  defp broadcast_event(event, state) do
    broadcast_event(event, nil, state)
  end

  defp broadcast_event(event, data, state) do
    message = if data, do: {event, data}, else: event
    
    Enum.each(state.subscribers, fn pid ->
      send(pid, {:oddsockets_event, message})
    end)
  end
end
