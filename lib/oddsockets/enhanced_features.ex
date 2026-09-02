defmodule OddSockets.EnhancedFeatures do
  @moduledoc """
  Enhanced Features for OddSockets Elixir SDK
  Provides 67 new Slack-like events with Elixir GenServer and async patterns
  """

  @timeout 10_000

  # ==================== THREAD EVENTS ====================

  @doc """
  Reply to a thread
  """
  def thread_reply(client, channel, parent_message_id, message, user_id, user_name) do
    params = %{
      channel: channel,
      parentMessageId: parent_message_id,
      message: message,
      userId: user_id,
      userName: user_name
    }
    emit_with_response(client, "thread_reply", params, "thread_reply_success")
  end

  @doc """
  Get thread data
  """
  def get_thread(client, thread_id) do
    emit_with_response(client, "get_thread", %{threadId: thread_id}, "thread_data")
  end

  @doc """
  Subscribe to thread updates
  """
  def subscribe_thread(client, thread_id, user_id) do
    params = %{threadId: thread_id, userId: user_id}
    emit_with_response(client, "subscribe_thread", params, "thread_subscribed")
  end

  @doc """
  Mark thread as read
  """
  def mark_thread_read(client, thread_id, user_id) do
    OddSockets.emit(client, "mark_thread_read", %{threadId: thread_id, userId: user_id})
  end

  @doc """
  Follow a thread
  """
  def follow_thread(client, thread_id, user_id) do
    OddSockets.emit(client, "follow_thread", %{threadId: thread_id, userId: user_id})
  end

  @doc """
  Unfollow a thread
  """
  def unfollow_thread(client, thread_id, user_id) do
    OddSockets.emit(client, "unfollow_thread", %{threadId: thread_id, userId: user_id})
  end

  # ==================== REACTION EVENTS ====================

  @doc """
  Add a reaction to a message
  """
  def add_reaction(client, message_id, channel, emoji, user_id, user_name) do
    params = %{
      messageId: message_id,
      channel: channel,
      emoji: emoji,
      userId: user_id,
      userName: user_name
    }
    OddSockets.emit(client, "add_reaction", params)
  end

  @doc """
  Remove a reaction from a message
  """
  def remove_reaction(client, message_id, channel, emoji, user_id) do
    params = %{
      messageId: message_id,
      channel: channel,
      emoji: emoji,
      userId: user_id
    }
    OddSockets.emit(client, "remove_reaction", params)
  end

  @doc """
  Get reactions for a message
  """
  def get_reactions(client, message_id) do
    emit_with_response(client, "get_reactions", %{messageId: message_id}, "message_reactions")
  end

  # ==================== READ RECEIPT EVENTS ====================

  @doc """
  Mark a message as read
  """
  def mark_read(client, message_id, channel, user_id, user_name) do
    params = %{
      messageId: message_id,
      channel: channel,
      userId: user_id,
      userName: user_name
    }
    OddSockets.emit(client, "mark_read", params)
  end

  @doc """
  Get unread counts for channels
  """
  def get_unread_counts(client, user_id, channels) do
    params = %{userId: user_id, channels: channels}
    emit_with_response(client, "get_unread_counts", params, "unread_counts")
  end

  @doc """
  Mark all messages in a channel as read
  """
  def mark_all_read(client, channel, user_id) do
    OddSockets.emit(client, "mark_all_read", %{channel: channel, userId: user_id})
  end

  # ==================== CHANNEL EVENTS ====================

  @doc """
  Create a new channel
  """
  def create_channel(client, name, type, description, topic, created_by, created_by_name) do
    params = %{
      name: name,
      type: type,
      description: description,
      topic: topic,
      createdBy: created_by,
      createdByName: created_by_name,
      members: []
    }
    emit_with_response(client, "create_channel", params, "channel_create_success")
  end

  @doc """
  Update channel properties
  """
  def update_channel(client, channel_id, updates, user_id) do
    params = %{
      channelId: channel_id,
      updates: updates,
      userId: user_id
    }
    OddSockets.emit(client, "update_channel", params)
  end

  @doc """
  Archive a channel
  """
  def archive_channel(client, channel_id, user_id) do
    OddSockets.emit(client, "archive_channel", %{channelId: channel_id, userId: user_id})
  end

  @doc """
  Invite a user to a channel
  """
  def invite_to_channel(client, channel_id, invited_user_id, invited_user_name, invited_by) do
    params = %{
      channelId: channel_id,
      invitedUserId: invited_user_id,
      invitedUserName: invited_user_name,
      invitedBy: invited_by
    }
    OddSockets.emit(client, "invite_to_channel", params)
  end

  @doc """
  Remove a user from a channel
  """
  def remove_from_channel(client, channel_id, removed_user_id, removed_by) do
    params = %{
      channelId: channel_id,
      removedUserId: removed_user_id,
      removedBy: removed_by
    }
    OddSockets.emit(client, "remove_from_channel", params)
  end

  @doc """
  Join a channel
  """
  def join_channel(client, channel_id, user_id, user_name) do
    params = %{
      channelId: channel_id,
      userId: user_id,
      userName: user_name
    }
    OddSockets.emit(client, "join_channel", params)
  end

  @doc """
  Leave a channel
  """
  def leave_channel(client, channel_id, user_id) do
    OddSockets.emit(client, "leave_channel", %{channelId: channel_id, userId: user_id})
  end

  @doc """
  Get channel members
  """
  def get_channel_members(client, channel_id) do
    emit_with_response(client, "get_channel_members", %{channelId: channel_id}, "channel_members")
  end

  # ==================== DIRECT MESSAGE EVENTS ====================

  @doc """
  Create a direct message conversation
  """
  def create_dm(client, user_ids, type) do
    params = %{userIds: user_ids, type: type}
    emit_with_response(client, "create_dm", params, "dm_create_success")
  end

  @doc """
  Send a direct message
  """
  def send_dm(client, conversation_id, message, user_id, user_name) do
    params = %{
      conversationId: conversation_id,
      message: message,
      userId: user_id,
      userName: user_name
    }
    OddSockets.emit(client, "send_dm", params)
  end

  @doc """
  Get DM conversations
  """
  def get_dm_conversations(client, user_id, include_archived) do
    params = %{userId: user_id, includeArchived: include_archived}
    emit_with_response(client, "get_dm_conversations", params, "dm_conversations")
  end

  # ==================== NOTIFICATION EVENTS ====================

  @doc """
  Subscribe to notifications
  """
  def subscribe_notifications(client, user_id) do
    OddSockets.emit(client, "subscribe_notifications", %{userId: user_id})
  end

  @doc """
  Mark a notification as read
  """
  def mark_notification_read(client, notification_id, user_id) do
    params = %{notificationId: notification_id, userId: user_id}
    OddSockets.emit(client, "mark_notification_read", params)
  end

  @doc """
  Mark all notifications as read
  """
  def mark_all_notifications_read(client, user_id) do
    OddSockets.emit(client, "mark_all_notifications_read", %{userId: user_id})
  end

  @doc """
  Clear all notifications
  """
  def clear_notifications(client, user_id) do
    OddSockets.emit(client, "clear_notifications", %{userId: user_id})
  end

  @doc """
  Get notifications
  """
  def get_notifications(client, user_id, limit, status \\ "all") do
    params = %{userId: user_id, limit: limit, status: status}
    emit_with_response(client, "get_notifications", params, "notifications_data")
  end

  # ==================== PRESENCE EVENTS ====================

  @doc """
  Set user status
  """
  def set_status(client, user_id, status) do
    OddSockets.emit(client, "set_status", %{userId: user_id, status: status})
  end

  @doc """
  Set custom status
  """
  def set_custom_status(client, user_id, emoji, text, expires_at \\ nil) do
    params = %{userId: user_id, emoji: emoji, text: text}
    params = if expires_at, do: Map.put(params, :expiresAt, expires_at), else: params
    OddSockets.emit(client, "set_custom_status", params)
  end

  @doc """
  Clear custom status
  """
  def clear_custom_status(client, user_id) do
    OddSockets.emit(client, "clear_custom_status", %{userId: user_id})
  end

  @doc """
  Set Do Not Disturb
  """
  def set_dnd(client, user_id, until \\ nil) do
    params = %{userId: user_id}
    params = if until, do: Map.put(params, :until, until), else: params
    OddSockets.emit(client, "set_dnd", params)
  end

  @doc """
  Clear Do Not Disturb
  """
  def clear_dnd(client, user_id) do
    OddSockets.emit(client, "clear_dnd", %{userId: user_id})
  end

  @doc """
  Start typing indicator
  """
  def start_typing(client, user_id, channel) do
    OddSockets.emit(client, "start_typing", %{userId: user_id, channel: channel})
  end

  @doc """
  Stop typing indicator
  """
  def stop_typing(client, user_id, channel) do
    OddSockets.emit(client, "stop_typing", %{userId: user_id, channel: channel})
  end

  @doc """
  Get user presence
  """
  def get_user_presence(client, user_ids) do
    emit_with_response(client, "get_user_presence", %{userIds: user_ids}, "user_presence_data")
  end

  # ==================== MESSAGE EDITING EVENTS ====================

  @doc """
  Edit a message
  """
  def edit_message(client, message_id, channel, new_content, user_id) do
    params = %{
      messageId: message_id,
      channel: channel,
      newContent: new_content,
      userId: user_id
    }
    OddSockets.emit(client, "edit_message", params)
  end

  @doc """
  Delete a message
  """
  def delete_message(client, message_id, channel, user_id) do
    params = %{
      messageId: message_id,
      channel: channel,
      userId: user_id
    }
    OddSockets.emit(client, "delete_message", params)
  end

  @doc """
  Pin a message
  """
  def pin_message(client, message_id, channel, user_id) do
    params = %{
      messageId: message_id,
      channel: channel,
      userId: user_id
    }
    OddSockets.emit(client, "pin_message", params)
  end

  @doc """
  Unpin a message
  """
  def unpin_message(client, message_id, channel, user_id) do
    params = %{
      messageId: message_id,
      channel: channel,
      userId: user_id
    }
    OddSockets.emit(client, "unpin_message", params)
  end

  @doc """
  Get pinned messages
  """
  def get_pinned_messages(client, channel) do
    emit_with_response(client, "get_pinned_messages", %{channel: channel}, "pinned_messages")
  end

  # ==================== SEARCH EVENTS ====================

  @doc """
  Search messages
  """
  def search_messages(client, query, user_id, limit) do
    params = %{query: query, userId: user_id, limit: limit}
    emit_with_response(client, "search_messages", params, "search_results")
  end

  @doc """
  Filter messages
  """
  def filter_messages(client, filters) do
    emit_with_response(client, "filter_messages", filters, "filter_results")
  end

  @doc """
  Search in a specific channel
  """
  def search_in_channel(client, channel, query, limit) do
    params = %{channel: channel, query: query, limit: limit}
    emit_with_response(client, "search_in_channel", params, "channel_search_results")
  end

  @doc """
  Search by user
  """
  def search_by_user(client, user_id, query, limit) do
    params = %{userId: user_id, limit: limit}
    params = if query, do: Map.put(params, :query, query), else: params
    emit_with_response(client, "search_by_user", params, "user_search_results")
  end

  # ==================== CHALLENGE / LEADERBOARD / ACHIEVEMENT EVENTS ====================

  @doc """
  Create a challenge (optionally ranked with a leaderboard).

  `params` keys: `challengeId`, `metric`, `ranked?`, `channel?`,
  `resultWebhookUrl?`, `standingsUrl?`. Returns the server ack.
  """
  def create_challenge(client, params) do
    emit_with_ack(client, "challenge_create", params, "challenge_create_success")
  end

  @doc """
  Report progress toward a challenge. Fire-and-forget; the worker echoes a
  `challenge_progress` broadcast and, for ranked challenges,
  `leaderboard_rank_change`.

  `params` keys: `challengeId`, `value`, `metric?`, `eventId?`, `cohort?`,
  `platform?`, `channel?`.
  """
  def report_progress(client, params) do
    OddSockets.emit(client, "challenge_progress", params)
  end

  @doc """
  Complete a challenge.

  `params` keys: `challengeId`, `outcome`, `eventId?`, `reward?` where `outcome`
  is one of `completed | failed | expired | conceded | tied`. Returns the ack.
  """
  def complete_challenge(client, params) do
    emit_with_ack(client, "challenge_complete", params, "challenge_complete_success")
  end

  @doc """
  Report achievement progress or unlock. Fire-and-forget. Pass `percentComplete`
  (0-100): `<100` broadcasts `achievement_progress`; `>=100` or omitted broadcasts
  `achievement_unlock`.

  `params` keys: `achievementId`, `name?`, `tier?`, `percentComplete?`,
  `challengeId?`, `channel?`.
  """
  def unlock_achievement(client, params) do
    OddSockets.emit(client, "achievement_unlock", params)
  end

  @doc """
  Fetch server-ordered leaderboard standings for a ranked challenge.

  `params` keys: `challengeId`, `limit?` (default 20), `offset?` (default 0).
  Returns the standings ack.
  """
  def get_standings(client, params) do
    params = params |> Map.put_new(:limit, 20) |> Map.put_new(:offset, 0)
    emit_with_ack(client, "challenge_standings", params, "challenge_standings_success")
  end

  @doc """
  Query persisted achievement state for the connected player.

  `params` keys: `achievementId?`. Returns the achievement state.
  """
  def get_achievements(client, params \\ %{}) do
    emit_with_ack(client, "achievement_query", params, "achievement_state")
  end

  @doc """
  Send a directed 1:1 challenge/invite to a specific player.

  `params` keys: `toUserId`, `type?` (default `match`), `payload?` (<=8KB),
  `ttl?` (default 300), `channel?`, `inviteId?`. Returns the invite ack.
  """
  def send_challenge_invite(client, params) do
    params = params |> Map.put_new(:type, "match") |> Map.put_new(:ttl, 300)
    emit_with_ack(client, "challenge_invite", params, "challenge_invite_success")
  end

  @doc """
  Accept or decline a received invite.

  `params` keys: `inviteId`, `accept`, `reason?`. Returns the reply ack.
  """
  def reply_challenge_invite(client, params) do
    emit_with_ack(client, "challenge_reply", params, "challenge_reply_success")
  end

  @doc """
  Cancel a pending invite you sent.

  `params` keys: `inviteId`. Returns the cancel ack.
  """
  def cancel_challenge_invite(client, params) do
    emit_with_ack(client, "challenge_invite_cancel", params, "challenge_invite_cancel_success")
  end

  @doc """
  Pull the connected player's still-pending invites (e.g. on reconnect).

  Returns `{invites: [...]}`.
  """
  def get_challenge_invites(client) do
    emit_with_ack(client, "challenge_invites_query", %{}, "challenge_invites")
  end

  # ==================== PRIVATE FUNCTIONS ====================

  # Like emit_with_response but also awaits a server "error" broadcast, failing
  # the call only when the error's "event" matches the emitted event (mirrors the
  # JS `socket.once('error', ...)` guard).
  defp emit_with_ack(client, event, params, response_event) do
    task = Task.async(fn ->
      receive do
        {:response, data} -> {:ok, data}
        {:error, message} -> {:error, message}
      after
        @timeout -> {:error, :timeout}
      end
    end)

    OddSockets.once(client, response_event, fn data ->
      send(task.pid, {:response, data})
    end)

    OddSockets.once(client, "error", fn err ->
      if Map.get(err, "event") == event do
        send(task.pid, {:error, Map.get(err, "message")})
      end
    end)

    OddSockets.emit(client, event, params)
    Task.await(task, @timeout + 1000)
  end

  defp emit_with_response(client, event, params, response_event) do
    task = Task.async(fn ->
      receive do
        {:response, data} -> {:ok, data}
      after
        @timeout -> {:error, :timeout}
      end
    end)

    OddSockets.once(client, response_event, fn data ->
      send(task.pid, {:response, data})
    end)

    OddSockets.emit(client, event, params)
    Task.await(task, @timeout + 1000)
  end
end
