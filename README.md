# OddSockets Elixir SDK

Official Elixir SDK for OddSockets real-time messaging platform. Provides a simple interface for pub/sub messaging with automatic manager discovery and worker load balancing.

## Installation

Add `oddsockets` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:oddsockets, "~> 1.0.0"}
  ]
end
```

## Quick Start

```elixir
# Start a client
{:ok, client} = OddSockets.start_link(api_key: "your-api-key")

# Get a channel
channel = OddSockets.channel(client, "my-channel")

# Subscribe to messages
:ok = OddSockets.Channel.subscribe(channel, fn message ->
  IO.inspect(message, label: "Received")
end)

# Publish a message
{:ok, result} = OddSockets.Channel.publish(channel, %{text: "Hello World!"})
```

## Features

- **Automatic Manager Discovery**: Connects to the optimal manager endpoint
- **Session Stickiness**: Clients stick to assigned workers across reconnections
- **Message Size Validation**: Industry-standard 32KB message size limits
- **Automatic Reconnection**: Exponential backoff reconnection strategy
- **Presence Tracking**: Real-time user presence and state management
- **Message History**: Configurable message history retention
- **Bulk Publishing**: Publish multiple messages efficiently
- **Event System**: Subscribe to connection and channel events

## API Reference

### Client Management

#### `OddSockets.start_link/1`

Start an OddSockets client.

```elixir
{:ok, client} = OddSockets.start_link(
  api_key: "your-api-key",
  user_id: "user123",           # optional
  auto_connect: true            # optional, default: true
)
```

#### `OddSockets.connect/1`

Manually connect to the platform.

```elixir
:ok = OddSockets.connect(client)
```

#### `OddSockets.disconnect/1`

Disconnect from the platform.

```elixir
:ok = OddSockets.disconnect(client)
```

#### `OddSockets.get_state/1`

Get current connection state.

```elixir
state = OddSockets.get_state(client)
# Returns: :disconnected | :connecting | :connected | :reconnecting
```

### Channel Operations

#### `OddSockets.channel/2`

Get or create a channel.

```elixir
channel = OddSockets.channel(client, "channel-name")
```

#### `OddSockets.Channel.subscribe/3`

Subscribe to channel messages.

```elixir
:ok = OddSockets.Channel.subscribe(channel, fn message ->
  IO.inspect(message)
end, %{
  max_history: 100,           # optional, default: 100
  retain_history: true,       # optional, default: true
  enable_presence: false      # optional, default: false
})
```

#### `OddSockets.Channel.publish/3`

Publish a message to the channel.

```elixir
{:ok, result} = OddSockets.Channel.publish(channel, %{
  text: "Hello World!",
  user: "alice"
}, %{
  ttl: 300,                   # optional, time to live in seconds
  metadata: %{priority: "high"} # optional
})
```

#### `OddSockets.Channel.get_history/2`

Get message history.

```elixir
{:ok, messages} = OddSockets.Channel.get_history(channel, %{
  count: 50,                  # optional, default: 50
  start: "2023-01-01T00:00:00Z", # optional
  end: "2023-01-02T00:00:00Z"    # optional
})
```

#### `OddSockets.Channel.get_presence/1`

Get current presence information.

```elixir
{:ok, presence} = OddSockets.Channel.get_presence(channel)
```

#### `OddSockets.Channel.update_state/2`

Update user state.

```elixir
{:ok, result} = OddSockets.Channel.update_state(channel, %{
  status: "online",
  location: "New York"
})
```

### Bulk Operations

#### `OddSockets.publish_bulk/2`

Publish multiple messages at once.

```elixir
messages = [
  %{channel: "channel1", message: %{text: "Hello"}},
  %{channel: "channel2", message: %{text: "World"}, options: %{ttl: 300}}
]

{:ok, results} = OddSockets.publish_bulk(client, messages)
```

### Event Handling

#### `OddSockets.subscribe_events/1`

Subscribe to client events.

```elixir
:ok = OddSockets.subscribe_events(client)

# Handle events in your process
receive do
  {:oddsockets_event, :connected} ->
    IO.puts("Connected to OddSockets!")
  
  {:oddsockets_event, {:error, reason}} ->
    IO.puts("Connection error: #{inspect(reason)}")
  
  {:oddsockets_event, {:worker_assigned, info}} ->
    IO.puts("Assigned to worker: #{info.worker_id}")
end
```

Available events:
- `:connecting` - Connection attempt started
- `:connected` - Successfully connected
- `:disconnected` - Disconnected from platform
- `{:error, reason}` - Connection error occurred
- `{:reconnecting, info}` - Reconnection attempt
- `{:worker_assigned, info}` - Worker assignment received
- `:max_reconnect_attempts_reached` - Reconnection failed

## Configuration

### Environment Variables

You can set default configuration using environment variables:

```bash
export ODDSOCKETS_API_KEY="your-api-key"
export ODDSOCKETS_MANAGER_URL="https://manager1.oddsockets.tyga.network"
```

### Application Configuration

Configure in your `config/config.exs`:

```elixir
config :oddsockets,
  api_key: "your-api-key",
  manager_url: "https://manager1.oddsockets.tyga.network"
```

## Error Handling

The SDK uses structured error handling:

```elixir
case OddSockets.Channel.publish(channel, message) do
  {:ok, result} ->
    IO.puts("Message published: #{result.message_id}")
  
  {:error, :client_not_connected} ->
    IO.puts("Client is not connected")
  
  {:error, reason} ->
    IO.puts("Publish failed: #{inspect(reason)}")
end
```

Common error types:
- `:client_not_connected` - Client is not connected to platform
- `:manager_offline` - Manager is not available
- `:invalid_response` - Invalid response from server
- `{:http_error, status}` - HTTP error with status code

## Message Size Limits

Messages are limited to 32KB (industry standard) for reliable real-time messaging:

```elixir
# This will raise an OddSockets.Error
large_message = String.duplicate("x", 40000)
OddSockets.Channel.publish(channel, large_message)
```

## Examples

### Basic Chat Application

```elixir
defmodule ChatApp do
  def start do
    # Start client
    {:ok, client} = OddSockets.start_link(api_key: "your-api-key")
    
    # Get channel
    channel = OddSockets.channel(client, "general")
    
    # Subscribe to messages
    :ok = OddSockets.Channel.subscribe(channel, &handle_message/1)
    
    # Send a message
    {:ok, _} = OddSockets.Channel.publish(channel, %{
      text: "Hello everyone!",
      user: "alice"
    })
    
    # Keep process alive
    Process.sleep(:infinity)
  end
  
  defp handle_message(message) do
    IO.puts("[#{message["user"]}]: #{message["text"]}")
  end
end
```

### Presence Tracking

```elixir
defmodule PresenceApp do
  def start do
    {:ok, client} = OddSockets.start_link(api_key: "your-api-key")
    channel = OddSockets.channel(client, "lobby")
    
    # Subscribe with presence enabled
    :ok = OddSockets.Channel.subscribe(channel, &handle_message/1, %{
      enable_presence: true
    })
    
    # Update user state
    {:ok, _} = OddSockets.Channel.update_state(channel, %{
      status: "online",
      location: "New York"
    })
    
    # Get current presence
    {:ok, presence} = OddSockets.Channel.get_presence(channel)
    IO.puts("Users online: #{presence.count}")
  end
  
  defp handle_message(%{"type" => "presence_change"} = message) do
    IO.puts("User #{message["user"]["user_id"]} #{message["action"]}")
  end
  
  defp handle_message(message) do
    IO.puts("Message: #{inspect(message)}")
  end
end
```

## Testing

Run the test suite:

```bash
mix test
```

## Documentation

Generate documentation:

```bash
mix docs
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Get a Free API Key

```bash
curl -X POST https://oddsockets.com/api/agent-signup \
  -H "Content-Type: application/json" \
  -d '{"email": "you@example.com", "agentName": "my-agent", "platform": "elixir"}'
# Then verify with the 6-digit code from your email:
curl -X POST https://oddsockets.com/api/agent-signup/verify \
  -H "Content-Type: application/json" \
  -d '{"email": "you@example.com", "code": "123456", "agentName": "my-agent"}'
```

## Plans

| | Free | Starter | Pro |
|---|---|---|---|
| **Price** | $0/mo | $49.99/mo | $299/mo |
| **MAU** | 100 | 1,000 | 50,000 |
| **Concurrent connections** | 50 | 1,000 | Unlimited |
| **Messages/day** | 10,000 | 4,320,000 | Unlimited |
| **Channels** | 10 | Unlimited | Unlimited |
| **Storage** | 100MB (24h) | 50GB (6 months) | Unlimited |

## Support

- [Documentation](https://docs.oddsockets.com/sdks/elixir)
- [Issue Tracker](https://github.com/jyswee/oddsockets-elixir-sdk/issues)
- [Email Support](mailto:support@oddsockets.com)

## License

MIT License - Copyright (c) 2026 Joe Wee, Tyga.Cloud Ltd. See [LICENSE](LICENSE) for details.

## Changelog

### 1.0.0
- Initial release
- Full JavaScript SDK pattern compliance
- Manager discovery and session stickiness
- Message size validation
- Automatic reconnection
- Presence tracking
- Message history
- Bulk publishing
- Event system
