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

## Enhanced Features

Beyond core pub/sub, OddSockets ships a Slack-like **enhanced surface** — reactions,
typing indicators, threads, read receipts, presence/status, notifications, DMs,
channel management, message editing and search. It lives in the
`OddSockets.EnhancedFeatures` module. The pattern is always the same:

1. **Send** an action with an `OddSockets.EnhancedFeatures.*` function (the client
   pid is always the first argument).
2. **Receive** the paired broadcast on your event stream: call
   `OddSockets.subscribe_events(client)` once, then match
   `{:oddsockets_event, {"<event>", payload}}` in your process mailbox.

```elixir
alias OddSockets.EnhancedFeatures

{:ok, client} = OddSockets.start_link(api_key: "YOUR_API_KEY", user_id: "alice")
:ok = OddSockets.connect(client)

# Enhanced broadcasts surface on the public event stream
:ok = OddSockets.subscribe_events(client)

channel = OddSockets.channel(client, "room-42")
:ok = OddSockets.Channel.subscribe(channel, fn _msg -> :ok end, %{enable_presence: true})

# Send-path: enhanced actions over the live socket (client pid first)
:ok = EnhancedFeatures.start_typing(client, "alice", "room-42")
:ok = EnhancedFeatures.add_reaction(client, "msg-1", "room-42", ":thumbsup:", "alice", "Alice")
:ok = EnhancedFeatures.thread_reply(client, "room-42", "msg-1", "Replying in the thread", "alice", "Alice")

# Receive-path: broadcasts from other users on the channel
receive do
  {:oddsockets_event, {"user_typing", payload}} ->
    IO.puts("#{payload["userId"]} is typing")

  {:oddsockets_event, {"reaction_added", payload}} ->
    IO.puts("#{payload["userId"]} reacted #{payload["emoji"]}")

  {:oddsockets_event, {"thread_reply", _payload}} ->
    IO.puts("New reply")
end
```

Each area exposes functions on `OddSockets.EnhancedFeatures`; the worker broadcasts
the paired events which surface on any process registered via
`OddSockets.subscribe_events/1`. Query functions (`get_*`, `search_*`) block and
return `{:ok, data}` (or `{:error, reason}`) with the worker response.

| Area | Requests (`OddSockets.EnhancedFeatures.*`) | Broadcast events (`{:oddsockets_event, {..}}`) |
|------|--------------------------------------------|------------------------------------------------|
| Typing | `start_typing`, `stop_typing` | `user_typing`, `user_stopped_typing` |
| Reactions | `add_reaction`, `remove_reaction`, `get_reactions` | `reaction_added`, `reaction_removed` |
| Threads | `thread_reply`, `get_thread`, `subscribe_thread`, `follow_thread`, `mark_thread_read` | `thread_reply`, `thread_subscribed`, `thread_followed`, `thread_read_updated` |
| Read receipts | `mark_read`, `mark_all_read`, `get_unread_counts` | `user_read`, `unread_count_updated`, `all_marked_read` |
| Messages | `edit_message`, `delete_message`, `pin_message`, `unpin_message`, `get_pinned_messages`, `search_messages` | `message_edited`, `message_deleted`, `message_pinned`, `message_unpinned` |
| Presence & status | `set_status`, `set_custom_status`, `set_dnd`, `get_user_presence` | `user_status_changed`, `custom_status_updated`, `dnd_status_changed` |
| Channels | `create_channel`, `update_channel`, `archive_channel`, `invite_to_channel`, `join_channel`, `leave_channel` | `channel_created`, `channel_updated`, `user_invited`, `user_joined_channel`, `user_left_channel` |
| DMs | `create_dm`, `send_dm`, `get_dm_conversations` | `dm_created`, `dm_received` |
| Notifications | `subscribe_notifications`, `get_notifications`, `mark_notification_read`, `clear_notifications` | `notification`, `notification_read`, `notifications_cleared` |
| Search | `search_messages`, `search_in_channel`, `search_by_user`, `filter_messages` | `{:ok, data}` results |

For any worker event not wrapped above, it still surfaces as
`{:oddsockets_event, {"<event>", payload}}` once you have called
`OddSockets.subscribe_events/1` — all enhanced broadcasts are forwarded to the
event stream.

## Configuration

### Manager URL

The client talks to a manager, which assigns it a worker. Point it at a
self-hosted or QA manager with `:manager_url`:

```elixir
{:ok, client} = OddSockets.start_link(
  api_key: "your-api-key",
  manager_url: "https://manager.internal.example"
)
```

Resolution order, highest first:

1. `:manager_url` passed to `OddSockets.start_link/1`
2. `config :oddsockets, manager_url: ...`
3. the `ODDSOCKETS_MANAGER_URL` environment variable
4. the public endpoint `https://connect.oddsockets.tyga.network`

Whatever resolves is used verbatim. If it is unreachable the connection fails
with that error - the SDK never quietly falls back to another manager, because
that would send a QA or self-hosted deployment to production unnoticed. A value
that is not an absolute `http://` or `https://` URL raises `ArgumentError` with
`Invalid managerUrl: <value>` when the client starts.

### Application Configuration

Configure in your `config/config.exs`:

```elixir
config :oddsockets,
  api_key: "your-api-key",
  manager_url: "https://manager.internal.example"
```

### Environment Variables

```bash
export ODDSOCKETS_API_KEY="your-api-key"
export ODDSOCKETS_MANAGER_URL="https://manager.internal.example"
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

## Get Accredited

<a href="https://tyga.games/accreditation"><img src="https://prodmedia.tyga.host/public/tyga.cloud/landing/tyga.games/tygagames-black-words.svg" alt="tyga.games accreditation" height="44"></a>

Prove you can build and operate real-time features on OddSockets — channels, presence, pub/sub, delivery guarantees and production liveops — on the stack itself. Three tiers (**TCU / TCA / TCP**), certified through **tyga.games** and delivered on ClassaaS.

[**Get accredited on tyga.games →**](https://tyga.games/accreditation)

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
