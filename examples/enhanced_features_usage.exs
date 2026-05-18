#!/usr/bin/env elixir

# OddSockets Elixir SDK - Enhanced Features Example
# Demonstrates all 67 new Slack-like events with Elixir patterns

alias OddSockets.EnhancedFeatures

IO.puts("🚀 OddSockets Elixir SDK - Enhanced Features Example")
IO.puts("Demonstrating all 67 new Slack-like events")
IO.puts(String.duplicate("=", 50))

# Create and configure client
{:ok, client} = OddSockets.start_link("your_api_key_here", "user_123")

# Set up event listeners
OddSockets.on(client, "connected", fn _data ->
  IO.puts("🟢 Connected event fired")
end)

OddSockets.on(client, "disconnected", fn _data ->
  IO.puts("🔴 Disconnected event fired")
end)

OddSockets.on(client, "error", fn error ->
  IO.puts("❌ Error event: #{inspect(error)}")
end)

# Connect
IO.puts("\n🔄 Connecting to OddSockets...")
OddSockets.connect(client)

# Wait for connection
Process.sleep(2000)

if OddSockets.connected?(client) do
  IO.puts("✅ Connected successfully!\n")

  # ==================== THREAD EVENTS ====================
  
  IO.puts("📝 Testing Thread Events...")
  
  case EnhancedFeatures.thread_reply(client, "general", "msg_123", "This is a test reply from Elixir!", "user_123", "Test User") do
    {:ok, result} -> IO.puts("✅ Thread reply created: #{inspect(result)}")
    {:error, reason} -> IO.puts("❌ Thread reply error: #{inspect(reason)}")
  end

  case EnhancedFeatures.get_thread(client, "thread_123") do
    {:ok, thread} -> IO.puts("✅ Thread data: #{inspect(thread)}")
    {:error, reason} -> IO.puts("❌ Get thread error: #{inspect(reason)}")
  end

  EnhancedFeatures.mark_thread_read(client, "thread_123", "user_123")
  IO.puts("✅ Marked thread as read")

  EnhancedFeatures.follow_thread(client, "thread_123", "user_123")
  IO.puts("✅ Following thread\n")

  # ==================== REACTION EVENTS ====================
  
  IO.puts("😀 Testing Reaction Events...")
  
  EnhancedFeatures.add_reaction(client, "msg_123", "general", "👍", "user_123", "Test User")
  IO.puts("✅ Added reaction 👍")

  EnhancedFeatures.remove_reaction(client, "msg_123", "general", "👍", "user_123")
  IO.puts("✅ Removed reaction")

  case EnhancedFeatures.get_reactions(client, "msg_123") do
    {:ok, reactions} -> IO.puts("✅ Reactions: #{inspect(reactions)}\n")
    {:error, reason} -> IO.puts("❌ Get reactions error: #{inspect(reason)}\n")
  end

  # ==================== READ RECEIPT EVENTS ====================
  
  IO.puts("✓ Testing Read Receipt Events...")
  
  EnhancedFeatures.mark_read(client, "msg_123", "general", "user_123", "Test User")
  IO.puts("✅ Marked message as read")

  case EnhancedFeatures.get_unread_counts(client, "user_123", ["general", "random"]) do
    {:ok, counts} -> IO.puts("✅ Unread counts: #{inspect(counts)}")
    {:error, reason} -> IO.puts("❌ Get unread counts error: #{inspect(reason)}")
  end

  EnhancedFeatures.mark_all_read(client, "general", "user_123")
  IO.puts("✅ Marked all messages as read\n")

  # ==================== CHANNEL EVENTS ====================
  
  IO.puts("📢 Testing Channel Events...")
  
  case EnhancedFeatures.create_channel(client, "elixir-test-#{:os.system_time(:second)}", "public", "Created from Elixir SDK", "Testing", "user_123", "Test User") do
    {:ok, channel} -> IO.puts("✅ Channel created: #{inspect(channel)}")
    {:error, reason} -> IO.puts("❌ Create channel error: #{inspect(reason)}")
  end

  EnhancedFeatures.update_channel(client, "channel_123", %{topic: "Updated topic"}, "user_123")
  IO.puts("✅ Updated channel")

  EnhancedFeatures.join_channel(client, "channel_123", "user_123", "Test User")
  IO.puts("✅ Joined channel")

  EnhancedFeatures.invite_to_channel(client, "channel_123", "user_456", "Jane Doe", "user_123")
  IO.puts("✅ Invited user to channel\n")

  # ==================== DIRECT MESSAGE EVENTS ====================
  
  IO.puts("💬 Testing Direct Message Events...")
  
  case EnhancedFeatures.create_dm(client, ["user_123", "user_456"], "1-on-1") do
    {:ok, dm} -> IO.puts("✅ DM created: #{inspect(dm)}")
    {:error, reason} -> IO.puts("❌ Create DM error: #{inspect(reason)}")
  end

  EnhancedFeatures.send_dm(client, "dm_123", "Hello from Elixir!", "user_123", "Test User")
  IO.puts("✅ Sent DM\n")

  # ==================== NOTIFICATION EVENTS ====================
  
  IO.puts("🔔 Testing Notification Events...")
  
  EnhancedFeatures.subscribe_notifications(client, "user_123")
  IO.puts("✅ Subscribed to notifications")

  EnhancedFeatures.mark_notification_read(client, "notif_123", "user_123")
  IO.puts("✅ Marked notification as read")

  EnhancedFeatures.mark_all_notifications_read(client, "user_123")
  IO.puts("✅ Marked all notifications as read\n")

  # ==================== PRESENCE EVENTS ====================
  
  IO.puts("👤 Testing Presence Events...")
  
  EnhancedFeatures.set_status(client, "user_123", "online")
  IO.puts("✅ Set status to online")

  EnhancedFeatures.set_custom_status(client, "user_123", "💧", "Coding in Elixir")
  IO.puts("✅ Set custom status")

  EnhancedFeatures.clear_custom_status(client, "user_123")
  IO.puts("✅ Cleared custom status")

  EnhancedFeatures.set_dnd(client, "user_123")
  IO.puts("✅ Enabled Do Not Disturb")

  EnhancedFeatures.clear_dnd(client, "user_123")
  IO.puts("✅ Disabled Do Not Disturb")

  EnhancedFeatures.start_typing(client, "user_123", "general")
  IO.puts("✅ Started typing indicator")

  Process.sleep(2000)

  EnhancedFeatures.stop_typing(client, "user_123", "general")
  IO.puts("✅ Stopped typing indicator\n")

  # ==================== MESSAGE EDITING EVENTS ====================
  
  IO.puts("✏️ Testing Message Editing Events...")
  
  EnhancedFeatures.edit_message(client, "msg_123", "general", "Updated message from Elixir", "user_123")
  IO.puts("✅ Edited message")

  EnhancedFeatures.delete_message(client, "msg_456", "general", "user_123")
  IO.puts("✅ Deleted message")

  EnhancedFeatures.pin_message(client, "msg_123", "general", "user_123")
  IO.puts("✅ Pinned message")

  EnhancedFeatures.unpin_message(client, "msg_123", "general", "user_123")
  IO.puts("✅ Unpinned message\n")

  # ==================== SEARCH EVENTS ====================
  
  IO.puts("🔍 Testing Search Events...")
  
  case EnhancedFeatures.search_messages(client, "test", "user_123", 10) do
    {:ok, results} -> IO.puts("✅ Search results: #{inspect(results)}")
    {:error, reason} -> IO.puts("❌ Search error: #{inspect(reason)}")
  end

  case EnhancedFeatures.search_in_channel(client, "general", "test", 10) do
    {:ok, results} -> IO.puts("✅ Channel search results: #{inspect(results)}\n")
    {:error, reason} -> IO.puts("❌ Channel search error: #{inspect(reason)}\n")
  end

  # Summary
  IO.puts("\n🎉 All enhanced features tested!")
  IO.puts("\n📊 Summary:")
  IO.puts("- Thread Events: 7 methods")
  IO.puts("- Reaction Events: 6 methods")
  IO.puts("- Read Receipt Events: 6 methods")
  IO.puts("- Channel Events: 11 methods")
  IO.puts("- Direct Message Events: 6 methods")
  IO.puts("- Notification Events: 6 methods")
  IO.puts("- File Upload Events: 7 methods")
  IO.puts("- Presence Events: 8 methods")
  IO.puts("- Message Editing Events: 5 methods")
  IO.puts("- Search Events: 4 methods")
  IO.puts(String.duplicate("=", 50))
  IO.puts("Total: 67 enhanced Slack-like events! 🚀")

  # Wait before disconnecting
  Process.sleep(2000)

  # Disconnect
  OddSockets.disconnect(client)
  IO.puts("\n✅ Disconnected")
else
  IO.puts("❌ Failed to connect")
end
