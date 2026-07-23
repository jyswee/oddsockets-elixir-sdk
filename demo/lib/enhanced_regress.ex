defmodule OddSocketsEnhancedRegress do
  @moduledoc """
  Enhanced-events two-client regression for the OddSockets Elixir SDK.

  Proves the RECEIVE path for enhanced (Slack-like) events: an action fired by
  one client (bob) is broadcast by the worker and surfaces on the OTHER
  client's public event stream (alice). Because publisher and subscriber are
  separate connections, an event reaching alice can only have travelled through
  the OddSockets worker - an honest end-to-end test, no local echo.

    bob -> EnhancedFeatures.start_typing/3  -> alice {:oddsockets_event, {"user_typing", _}}
    bob -> EnhancedFeatures.add_reaction/6  -> alice {:oddsockets_event, {"reaction_added", _}}

  Run with: mix run -e "OddSocketsEnhancedRegress.run()"
  """

  alias OddSockets.EnhancedFeatures

  @timeout_ms 20_000

  def run do
    api_key = get_api_key!()
    channel_name = "enh-#{:crypto.strong_rand_bytes(5) |> Base.encode16(case: :lower)}"

    IO.puts("[connect] connecting both clients...")

    {:ok, alice} = OddSockets.start_link(api_key: api_key, user_id: "alice", auto_connect: false)
    {:ok, bob} = OddSockets.start_link(api_key: api_key, user_id: "bob", auto_connect: false)

    :ok = OddSockets.connect(alice)
    :ok = OddSockets.connect(bob)

    IO.puts("[alice] worker #{worker_id(alice)}")
    IO.puts("[bob]   worker #{worker_id(bob)}")
    IO.puts("[connect] alice = #{OddSockets.get_state(alice)}, bob = #{OddSockets.get_state(bob)}")

    # Enhanced broadcasts must surface on alice's PUBLIC event stream.
    :ok = OddSockets.subscribe_events(alice)

    alice_ch = OddSockets.channel(alice, channel_name)
    bob_ch = OddSockets.channel(bob, channel_name)

    :ok = OddSockets.Channel.subscribe(alice_ch, fn _m -> :ok end, %{enable_presence: true})
    :ok = OddSockets.Channel.subscribe(bob_ch, fn _m -> :ok end, %{enable_presence: true})
    IO.puts("[both] subscribed to #{channel_name}")

    # Let room membership settle, then fire enhanced actions from bob.
    Process.sleep(500)

    IO.puts("[bob] EnhancedFeatures.start_typing(bob) ...")
    :ok = EnhancedFeatures.start_typing(bob, "bob", channel_name)

    {:ok, ack} = OddSockets.Channel.publish(bob_ch, %{"text" => "react to me"})
    msg_id = ack["message_id"] || ack["messageId"]
    IO.puts("[bob] published messageId=#{msg_id}, EnhancedFeatures.add_reaction :thumbsup: ...")
    :ok = EnhancedFeatures.add_reaction(bob, msg_id, channel_name, ":thumbsup:", "bob", "Bob")

    await_broadcasts(false, false)

    OddSockets.disconnect(alice)
    OddSockets.disconnect(bob)
    IO.puts("\nOK - enhanced broadcast receive-path verified (user_typing + reaction_added)")
    System.halt(0)
  end

  # Waits until BOTH enhanced broadcasts have reached alice's event stream.
  defp await_broadcasts(true, true), do: :ok

  defp await_broadcasts(got_typing, got_reaction) do
    receive do
      {:oddsockets_event, {"user_typing", payload}} ->
        if Map.get(payload, "userId") == "bob" do
          IO.puts("[alice] received 'user_typing' from bob (channel #{Map.get(payload, "channel")}) - broadcast round-trip.")
          await_broadcasts(true, got_reaction)
        else
          await_broadcasts(got_typing, got_reaction)
        end

      {:oddsockets_event, {"reaction_added", payload}} ->
        emoji = Map.get(payload, "emoji")
        if emoji do
          IO.puts("[alice] received 'reaction_added' (#{emoji}) from #{Map.get(payload, "userId")} - broadcast round-trip.")
          await_broadcasts(got_typing, true)
        else
          await_broadcasts(got_typing, got_reaction)
        end

      _other ->
        await_broadcasts(got_typing, got_reaction)
    after
      @timeout_ms ->
        IO.puts("\nTIMEOUT - enhanced broadcast not received within #{div(@timeout_ms, 1000)}s (typing=#{got_typing} reaction=#{got_reaction})")
        System.halt(2)
    end
  end

  defp worker_id(client) do
    case OddSockets.get_worker_info(client) do
      %{worker_id: id} -> id
      _ -> "unknown"
    end
  end

  defp get_api_key! do
    case System.get_env("ODDSOCKETS_API_KEY") do
      nil -> IO.puts("ODDSOCKETS_API_KEY is not set."); System.halt(1)
      "" -> IO.puts("ODDSOCKETS_API_KEY is empty."); System.halt(1)
      api_key -> api_key
    end
  end
end
