defmodule OddSockets.Channel do
  @moduledoc """
  Channel class for pub/sub messaging

  Provides methods for subscribing, publishing, and managing presence
  on a specific channel within the OddSockets platform.
  """

  use GenServer
  require Logger

  alias OddSockets.{MessageSizeValidator, Types, Error}

  @type state :: %{
          name: String.t(),
          client: pid(),
          subscribed: boolean(),
          subscribing: boolean(),
          options: map(),
          presence: %{String.t() => map()},
          message_history: [map()],
          max_history_size: non_neg_integer(),
          subscribers: [function()]
        }

  @default_max_history 100

  ## Public API

  @doc """
  Start a Channel process.

  This is typically called internally by the OddSockets client.
  """
  @spec start_link(String.t(), pid()) :: GenServer.on_start()
  def start_link(name, client) do
    GenServer.start_link(__MODULE__, {name, client})
  end

  @doc """
  Subscribe to the channel.

  ## Options

    * `:max_history` - Maximum history messages to retain (default: 100)
    * `:retain_history` - Whether to retain message history (default: true)
    * `:enable_presence` - Whether to enable presence tracking (default: false)

  ## Examples

      :ok = OddSockets.Channel.subscribe(channel, fn message ->
        IO.inspect(message, label: "Received")
      end)

      :ok = OddSockets.Channel.subscribe(channel, callback, %{
        max_history: 50,
        enable_presence: true
      })

  """
  @spec subscribe(pid(), function(), map()) :: :ok | {:error, term()}
  def subscribe(channel, callback, options \\ %{}) when is_function(callback) do
    GenServer.call(channel, {:subscribe, callback, options}, 10_000)
  end

  @doc """
  Unsubscribe from the channel.
  """
  @spec unsubscribe(pid()) :: :ok | {:error, term()}
  def unsubscribe(channel) do
    GenServer.call(channel, :unsubscribe, 5_000)
  end

  @doc """
  Publish a message to the channel.

  ## Options

    * `:ttl` - Time to live in seconds
    * `:metadata` - Additional message metadata

  ## Examples

      {:ok, result} = OddSockets.Channel.publish(channel, %{text: "Hello World!"})

      {:ok, result} = OddSockets.Channel.publish(channel, "Simple message", %{
        ttl: 300,
        metadata: %{priority: "high"}
      })

  """
  @spec publish(pid(), term(), map()) :: {:ok, map()} | {:error, term()}
  def publish(channel, message, options \\ %{}) do
    GenServer.call(channel, {:publish, message, options}, 10_000)
  end

  @doc """
  Get message history for the channel.

  ## Options

    * `:count` - Number of messages to retrieve (default: 50)
    * `:start` - Start time (ISO string)
    * `:end` - End time (ISO string)

  """
  @spec get_history(pid(), map()) :: {:ok, [map()]} | {:error, term()}
  def get_history(channel, options \\ %{}) do
    GenServer.call(channel, {:get_history, options}, 10_000)
  end

  @doc """
  Get current presence information.
  """
  @spec get_presence(pid()) :: {:ok, map()} | {:error, term()}
  def get_presence(channel) do
    GenServer.call(channel, :get_presence, 5_000)
  end

  @doc """
  Update user state.
  """
  @spec update_state(pid(), map()) :: {:ok, map()} | {:error, term()}
  def update_state(channel, state) when is_map(state) do
    GenServer.call(channel, {:update_state, state}, 5_000)
  end

  @doc """
  Get channel subscription status.
  """
  @spec subscribed?(pid()) :: boolean()
  def subscribed?(channel) do
    GenServer.call(channel, :subscribed?)
  end

  @doc """
  Get channel name.
  """
  @spec get_name(pid()) :: String.t()
  def get_name(channel) do
    GenServer.call(channel, :get_name)
  end

  @doc """
  Get current presence map.
  """
  @spec get_presence_map(pid()) :: %{String.t() => map()}
  def get_presence_map(channel) do
    GenServer.call(channel, :get_presence_map)
  end

  @doc """
  Get cached message history.
  """
  @spec get_cached_history(pid()) :: [map()]
  def get_cached_history(channel) do
    GenServer.call(channel, :get_cached_history)
  end

  ## GenServer Callbacks

  @impl true
  def init({name, client}) do
    state = %{
      name: name,
      client: client,
      subscribed: false,
      subscribing: false,
      options: %{},
      presence: %{},
      message_history: [],
      max_history_size: @default_max_history,
      subscribers: []
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:subscribe, callback, options}, _from, state) do
    if state.subscribed or state.subscribing do
      # Add callback to existing subscription
      new_subscribers = [callback | state.subscribers]
      new_state = %{state | subscribers: new_subscribers}
      {:reply, :ok, new_state}
    else
      case is_client_connected?(state.client) do
        false ->
          {:reply, {:error, :client_not_connected}, state}
        
        true ->
          new_options = Map.merge(%{
            max_history: @default_max_history,
            retain_history: true,
            enable_presence: false
          }, options)
          
          new_state = %{state |
            subscribing: true,
            options: new_options,
            max_history_size: new_options.max_history,
            subscribers: [callback]
          }
          
          case send_subscribe_request(new_state) do
            :ok ->
              final_state = %{new_state | subscribed: true, subscribing: false}
              {:reply, :ok, final_state}
            
            {:error, reason} ->
              error_state = %{new_state | subscribing: false}
              {:reply, {:error, reason}, error_state}
          end
      end
    end
  end

  def handle_call(:unsubscribe, _from, state) do
    if not state.subscribed do
      {:reply, :ok, state}
    else
      case is_client_connected?(state.client) do
        false ->
          {:reply, {:error, :client_not_connected}, state}
        
        true ->
          case send_unsubscribe_request(state) do
            :ok ->
              new_state = %{state |
                subscribed: false,
                subscribers: []
              }
              {:reply, :ok, new_state}
            
            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
      end
    end
  end

  def handle_call({:publish, message, options}, _from, state) do
    case is_client_connected?(state.client) do
      false ->
        {:reply, {:error, :client_not_connected}, state}
      
      true ->
        try do
          MessageSizeValidator.validate_message_size(message)
          
          case send_publish_request(message, options, state) do
            {:ok, result} ->
              {:reply, {:ok, result}, state}
            
            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        rescue
          e in Error ->
            {:reply, {:error, e.message}, state}
        end
    end
  end

  def handle_call({:get_history, options}, _from, state) do
    case is_client_connected?(state.client) do
      false ->
        {:reply, {:error, :client_not_connected}, state}
      
      true ->
        case send_history_request(options, state) do
          {:ok, messages} ->
            {:reply, {:ok, messages}, state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call(:get_presence, _from, state) do
    case is_client_connected?(state.client) do
      false ->
        {:reply, {:error, :client_not_connected}, state}
      
      true ->
        case send_presence_request(state) do
          {:ok, presence_data} ->
            {:reply, {:ok, presence_data}, state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call({:update_state, user_state}, _from, state) do
    case is_client_connected?(state.client) do
      false ->
        {:reply, {:error, :client_not_connected}, state}
      
      true ->
        case send_state_update_request(user_state, state) do
          {:ok, result} ->
            {:reply, {:ok, result}, state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  def handle_call(:subscribed?, _from, state) do
    {:reply, state.subscribed, state}
  end

  def handle_call(:get_name, _from, state) do
    {:reply, state.name, state}
  end

  def handle_call(:get_presence_map, _from, state) do
    {:reply, state.presence, state}
  end

  def handle_call(:get_cached_history, _from, state) do
    {:reply, state.message_history, state}
  end

  @impl true
  def handle_info({:websocket_message, data}, state) do
    new_state = handle_websocket_message(data, state)
    {:noreply, new_state}
  end

  ## Private Functions

  defp is_client_connected?(client) do
    try do
      OddSockets.get_state(client) == :connected
    rescue
      _ -> false
    end
  end

  defp send_subscribe_request(state) do
    # Mock implementation - in a real implementation, this would
    # send a WebSocket message to the worker
    Logger.info("Subscribing to channel: #{state.name}")
    :ok
  end

  defp send_unsubscribe_request(state) do
    # Mock implementation
    Logger.info("Unsubscribing from channel: #{state.name}")
    :ok
  end

  defp send_publish_request(message, options, state) do
    # Mock implementation
    Logger.info("Publishing to channel #{state.name}: #{inspect(message)}")
    
    result = %{
      channel: state.name,
      message_id: generate_message_id(),
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      options: options
    }
    
    {:ok, result}
  end

  defp send_history_request(options, state) do
    # Mock implementation
    count = Map.get(options, :count, 50)
    Logger.info("Requesting #{count} history messages for channel: #{state.name}")
    
    # Return cached history for now
    messages = Enum.take(state.message_history, count)
    {:ok, messages}
  end

  defp send_presence_request(state) do
    # Mock implementation
    Logger.info("Requesting presence for channel: #{state.name}")
    
    presence_data = %{
      channel: state.name,
      occupants: Map.values(state.presence),
      count: map_size(state.presence)
    }
    
    {:ok, presence_data}
  end

  defp send_state_update_request(user_state, state) do
    # Mock implementation
    Logger.info("Updating state for channel #{state.name}: #{inspect(user_state)}")
    
    result = %{
      channel: state.name,
      state: user_state,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }
    
    {:ok, result}
  end

  defp handle_websocket_message(%{"type" => "message"} = data, state) do
    # Add to history if enabled
    new_state = if state.options[:retain_history] do
      new_history = [data | state.message_history]
      |> Enum.take(state.max_history_size)
      
      %{state | message_history: new_history}
    else
      state
    end
    
    # Notify subscribers
    Enum.each(state.subscribers, fn callback ->
      try do
        callback.(data)
      rescue
        e ->
          Logger.error("Error in message callback: #{inspect(e)}")
      end
    end)
    
    new_state
  end

  defp handle_websocket_message(%{"type" => "presence"} = data, state) do
    # Update presence map
    new_presence = case data do
      %{"occupants" => occupants} when is_list(occupants) ->
        occupants
        |> Enum.map(fn occupant -> {occupant["userId"], occupant} end)
        |> Map.new()
      
      _ -> state.presence
    end
    
    %{state | presence: new_presence}
  end

  defp handle_websocket_message(%{"type" => "presence_change"} = data, state) do
    new_presence = case data do
      %{"action" => "join", "user" => user} ->
        Map.put(state.presence, user["userId"], user)
      
      %{"action" => "leave", "user" => user} ->
        Map.delete(state.presence, user["userId"])
      
      _ -> state.presence
    end
    
    %{state | presence: new_presence}
  end

  defp handle_websocket_message(_data, state) do
    # Ignore unknown message types
    state
  end

  defp generate_message_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end
end
