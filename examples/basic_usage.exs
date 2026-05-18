#!/usr/bin/env elixir

# Basic usage example for OddSockets Elixir SDK
# Run with: elixir examples/basic_usage.exs

defmodule BasicUsageExample do
  @moduledoc """
  Basic usage example demonstrating core OddSockets functionality.
  """

  def run do
    IO.puts("🚀 OddSockets Elixir SDK - Basic Usage Example")
    IO.puts("=" |> String.duplicate(50))

    # Start the client
    IO.puts("\n📡 Starting OddSockets client...")
    {:ok, client} = OddSockets.start_link(
      api_key: get_api_key(),
      user_id: "example_user_#{:rand.uniform(1000)}",
      auto_connect: true
    )

    # Subscribe to client events
    :ok = OddSockets.subscribe_events(client)
    IO.puts("✅ Client started and event subscription enabled")

    # Wait for connection
    wait_for_connection()

    # Get a channel
    IO.puts("\n📺 Creating channel...")
    channel = OddSockets.channel(client, "example-channel")
    IO.puts("✅ Channel created: example-channel")

    # Subscribe to channel messages
    IO.puts("\n🔔 Subscribing to channel messages...")
    :ok = OddSockets.Channel.subscribe(channel, &handle_message/1, %{
      max_history: 50,
      retain_history: true,
      enable_presence: true
    })
    IO.puts("✅ Subscribed to channel messages")

    # Publish some messages
    IO.puts("\n📤 Publishing messages...")
    publish_example_messages(channel)

    # Get message history
    IO.puts("\n📜 Getting message history...")
    case OddSockets.Channel.get_history(channel, %{count: 10}) do
      {:ok, messages} ->
        IO.puts("✅ Retrieved #{length(messages)} messages from history")
      {:error, reason} ->
        IO.puts("❌ Failed to get history: #{inspect(reason)}")
    end

    # Get presence information
    IO.puts("\n👥 Getting presence information...")
    case OddSockets.Channel.get_presence(channel) do
      {:ok, presence} ->
        IO.puts("✅ Current presence: #{presence.count} users online")
      {:error, reason} ->
        IO.puts("❌ Failed to get presence: #{inspect(reason)}")
    end

    # Update user state
    IO.puts("\n🔄 Updating user state...")
    case OddSockets.Channel.update_state(channel, %{
      status: "online",
      location: "Example City",
      mood: "excited"
    }) do
      {:ok, _result} ->
        IO.puts("✅ User state updated")
      {:error, reason} ->
        IO.puts("❌ Failed to update state: #{inspect(reason)}")
    end

    # Demonstrate bulk publishing
    IO.puts("\n📦 Bulk publishing messages...")
    bulk_messages = [
      %{channel: "example-channel", message: %{text: "Bulk message 1", type: "bulk"}},
      %{channel: "example-channel", message: %{text: "Bulk message 2", type: "bulk"}},
      %{channel: "example-channel", message: %{text: "Bulk message 3", type: "bulk"}}
    ]

    case OddSockets.publish_bulk(client, bulk_messages) do
      {:ok, results} ->
        successful = Enum.count(results, & &1.success)
        IO.puts("✅ Bulk publish completed: #{successful}/#{length(results)} successful")
      {:error, reason} ->
        IO.puts("❌ Bulk publish failed: #{inspect(reason)}")
    end

    # Get client information
    IO.puts("\n📊 Client information:")
    IO.puts("   State: #{OddSockets.get_state(client)}")
    IO.puts("   Client ID: #{OddSockets.get_client_identifier(client)}")
    
    case OddSockets.get_worker_info(client) do
      nil ->
        IO.puts("   Worker: Not assigned")
      worker_info ->
        IO.puts("   Worker: #{worker_info.worker_id} (#{worker_info.worker_url})")
    end

    # Listen for events for a while
    IO.puts("\n👂 Listening for events (10 seconds)...")
    listen_for_events(10_000)

    # Clean up
    IO.puts("\n🧹 Cleaning up...")
    :ok = OddSockets.Channel.unsubscribe(channel)
    :ok = OddSockets.disconnect(client)
    IO.puts("✅ Disconnected and cleaned up")

    IO.puts("\n🎉 Example completed successfully!")
  end

  defp get_api_key do
    case System.get_env("ODDSOCKETS_API_KEY") do
      nil ->
        IO.puts("⚠️  Using demo API key. Set ODDSOCKETS_API_KEY environment variable for your own key.")
        "demo-api-key-for-testing"
      api_key ->
        IO.puts("✅ Using API key from environment")
        api_key
    end
  end

  defp wait_for_connection do
    receive do
      {:oddsockets_event, :connected} ->
        IO.puts("✅ Connected to OddSockets!")
      
      {:oddsockets_event, {:worker_assigned, info}} ->
        IO.puts("✅ Assigned to worker: #{info.worker_id}")
        wait_for_connection()
      
      {:oddsockets_event, {:error, reason}} ->
        IO.puts("❌ Connection error: #{inspect(reason)}")
        wait_for_connection()
      
      {:oddsockets_event, :connecting} ->
        IO.puts("🔄 Connecting...")
        wait_for_connection()
    after
      15_000 ->
        IO.puts("⏰ Connection timeout - continuing anyway")
    end
  end

  defp handle_message(message) do
    case message do
      %{"text" => text, "user" => user} ->
        IO.puts("💬 [#{user}]: #{text}")
      
      %{"type" => "presence_change", "action" => action, "user" => user} ->
        IO.puts("👤 User #{user["user_id"]} #{action}")
      
      %{"text" => text} ->
        IO.puts("💬 Message: #{text}")
      
      _ ->
        IO.puts("📨 Received: #{inspect(message)}")
    end
  end

  defp publish_example_messages(channel) do
    messages = [
      %{text: "Hello from Elixir SDK!", user: "elixir_example", timestamp: DateTime.utc_now()},
      %{text: "This is a test message", user: "elixir_example", priority: "normal"},
      %{text: "OddSockets is working great! 🎉", user: "elixir_example", mood: "excited"}
    ]

    Enum.each(messages, fn message ->
      case OddSockets.Channel.publish(channel, message, %{ttl: 300}) do
        {:ok, result} ->
          IO.puts("✅ Published message: #{result.message_id}")
        {:error, reason} ->
          IO.puts("❌ Failed to publish: #{inspect(reason)}")
      end
      
      # Small delay between messages
      Process.sleep(500)
    end)
  end

  defp listen_for_events(timeout) do
    receive do
      {:oddsockets_event, event} ->
        case event do
          :connected ->
            IO.puts("🔗 Event: Connected")
          
          :disconnected ->
            IO.puts("🔌 Event: Disconnected")
          
          {:error, reason} ->
            IO.puts("❌ Event: Error - #{inspect(reason)}")
          
          {:reconnecting, info} ->
            IO.puts("🔄 Event: Reconnecting (attempt #{info.attempt}/#{info.max_attempts})")
          
          {:worker_assigned, info} ->
            IO.puts("🏭 Event: Worker assigned - #{info.worker_id}")
          
          :max_reconnect_attempts_reached ->
            IO.puts("🚫 Event: Max reconnect attempts reached")
          
          _ ->
            IO.puts("📡 Event: #{inspect(event)}")
        end
        
        listen_for_events(timeout)
    after
      timeout ->
        IO.puts("⏰ Event listening timeout")
    end
  end
end

# Run the example
try do
  BasicUsageExample.run()
rescue
  e ->
    IO.puts("\n❌ Example failed with error:")
    IO.puts("   #{Exception.format(:error, e, __STACKTRACE__)}")
    System.halt(1)
end
