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
          api_key: String.t(),
          user_id: String.t() | nil,
          options: map()
        }

  @type state :: %{
          config: config(),
          socket: pid() | nil,
          worker_url: String.t() | nil,
          worker_id: String.t() | nil,
          channels: %{String.t() => pid()},
          connection_state: atom(),
          reconnect_attempts: non_neg_integer(),
          max_reconnect_attempts: non_neg_integer(),
          reconnect_delay: non_neg_integer(),
          client_identifier: String.t(),
          session_info: map() | nil,
          subscribers: [pid()]
        }

  @max_reconnect_attempts 5
  @initial_reconnect_delay 1000
  @manager_url "https://manager1.oddsockets.tyga.network"

  ## Public API

  @doc """
  Start an OddSockets client.

  ## Options

    * `:api_key` - Your OddSockets API key (required)
    * `:user_id` - User ID (defaults to API key's user)
    * `:options` - Additional connection options
    * `:auto_connect` - Whether to auto-connect (default: true)

  ## Examples

      {:ok, client} = OddSockets.start_link(api_key: "your-api-key")

      {:ok, client} = OddSockets.start_link(
        api_key: "your-api-key",
        user_id: "user123",
        auto_connect: false
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

  ## GenServer Callbacks

  @impl true
  def init(config) do
    state = %{
      config: config,
      socket: nil,
      worker_url: nil,
      worker_id: nil,
      channels: %{},
      connection_state: :disconnected,
      reconnect_attempts: 0,
      max_reconnect_attempts: @max_reconnect_attempts,
      reconnect_delay: @initial_reconnect_delay,
      client_identifier: generate_client_identifier(config),
      session_info: nil,
      subscribers: []
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

  def handle_call(:connect, _from, state) do
    case do_connect(state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:disconnect, _from, state) do
    new_state = do_disconnect(state)
    {:reply, :ok, new_state}
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
  def handle_info(:connect, state) do
    case do_connect(state) do
      {:ok, new_state} ->
        {:noreply, new_state}
      {:error, _reason} ->
        # Schedule reconnect
        new_state = schedule_reconnect(state)
        {:noreply, new_state}
    end
  end

  def handle_info(:reconnect, state) do
    send(self(), :connect)
    {:noreply, state}
  end

  def handle_info({:websocket_message, message}, state) do
    handle_websocket_message(message, state)
    {:noreply, state}
  end

  def handle_info({:websocket_closed, _reason}, state) do
    new_state = %{state | connection_state: :disconnected, socket: nil}
    broadcast_event(:disconnected, new_state)
    
    # Auto-reconnect unless manually disconnected
    new_state = schedule_reconnect(new_state)
    {:noreply, new_state}
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
    api_key = Keyword.fetch!(opts, :api_key)
    
    %{
      api_key: api_key,
      user_id: Keyword.get(opts, :user_id),
      options: Keyword.get(opts, :options, %{}),
      auto_connect: Keyword.get(opts, :auto_connect, true)
    }
  end

  defp do_connect(state) do
    state = %{state | connection_state: :connecting}
    broadcast_event(:connecting, state)

    with {:ok, worker_assignment} <- get_worker_assignment(state),
         {:ok, socket} <- connect_to_worker(worker_assignment, state) do
      
      new_state = %{state |
        connection_state: :connected,
        socket: socket,
        worker_url: worker_assignment.url,
        worker_id: worker_assignment.worker_id,
        session_info: worker_assignment.session,
        reconnect_attempts: 0,
        reconnect_delay: @initial_reconnect_delay
      }
      
      broadcast_event(:connected, new_state)
      broadcast_event(:worker_assigned, worker_assignment, new_state)
      
      {:ok, new_state}
    else
      {:error, reason} ->
        new_state = %{state | connection_state: :disconnected}
        broadcast_event(:error, reason, new_state)
        {:error, reason}
    end
  end

  defp do_disconnect(state) do
    if state.socket do
      # Close WebSocket connection
      send(state.socket, :close)
    end
    
    new_state = %{state |
      connection_state: :disconnected,
      socket: nil,
      worker_url: nil,
      worker_id: nil
    }
    
    broadcast_event(:disconnected, new_state)
    new_state
  end

  defp get_worker_assignment(state) do
    # Step 1: Discover the optimal manager URL automatically (following JavaScript SDK pattern)
    manager_url = ManagerDiscovery.discover_manager_url(state.config.api_key)
    url = "#{manager_url}/api/cluster/select-worker"
    
    params = %{
      "apiKey" => state.config.api_key,
      "userId" => state.config.user_id || state.client_identifier,
      "clientIdentifier" => state.client_identifier
    }
    
    headers = [
      {"User-Agent", "OddSockets-Elixir-SDK/1.0.0"},
      {"Content-Type", "application/json"}
    ]
    
    case HTTPoison.get(url, headers, params: params, timeout: 10_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"url" => worker_url, "workerId" => worker_id} = response} ->
            assignment = %{
              url: worker_url,
              worker_id: worker_id,
              session: Map.get(response, "session"),
              client_identifier: state.client_identifier,
              manager_url: manager_url  # Include discovered manager URL for debugging
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

  defp connect_to_worker(assignment, state) do
    # For now, return a mock socket - in a real implementation,
    # this would establish a WebSocket connection
    socket_pid = spawn_link(fn -> websocket_loop() end)
    {:ok, socket_pid}
  end

  defp websocket_loop do
    receive
      :close -> :ok
      _ -> websocket_loop()
    end
  end

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

  defp handle_websocket_message(message, state) do
    # Forward WebSocket messages to appropriate channels
    case Jason.decode(message) do
      {:ok, %{"channel" => channel_name} = data} ->
        case Map.get(state.channels, channel_name) do
          nil -> :ok
          channel_pid -> send(channel_pid, {:websocket_message, data})
        end
      
      {:error, _} ->
        Logger.warning("Failed to decode WebSocket message: #{inspect(message)}")
    end
  end

  defp generate_client_identifier(config) do
    base_id = config.user_id || "default"
    api_key_hash = hash_string(config.api_key)
    "#{api_key_hash}_#{base_id}"
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
