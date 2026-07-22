defmodule OddSocketsDemo do
  @moduledoc """
  Two-client round-trip demo for the OddSockets Elixir SDK.

  A genuine end-to-end round-trip using TWO independent clients:

    * a SUBSCRIBER ("alice") that listens on a channel
    * a PUBLISHER  ("bob")   that sends one message

  Because they are separate connections, a message reaching the subscriber can
  ONLY have travelled through the OddSockets worker - it cannot be a local echo.
  A matched nonce here is proof of a real Socket.IO round-trip. No mocks.

  Exercised surface: connect -> subscribe (+presence) -> publish -> receive
  -> presence -> unsubscribe -> disconnect.

  Run with: mix run -e "OddSocketsDemo.run()"
  """

  @timeout_ms 15_000

  def run do
    api_key = get_api_key!()

    # A unique channel and nonce so we only ever match our own run.
    channel_name = "demo-#{100_000 + :rand.uniform(900_000)}"
    nonce = "n-" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
    parent = self()

    IO.puts("[connect] connecting both clients...")

    {:ok, subscriber} =
      OddSockets.start_link(api_key: api_key, user_id: "alice", auto_connect: false)

    {:ok, publisher} =
      OddSockets.start_link(api_key: api_key, user_id: "bob", auto_connect: false)

    :ok = OddSockets.connect(subscriber)
    :ok = OddSockets.connect(publisher)

    IO.puts("[alice] worker #{worker_id(subscriber)}")
    IO.puts("[bob]   worker #{worker_id(publisher)}")

    IO.puts(
      "[connect] alice = #{OddSockets.get_state(subscriber)}, " <>
        "bob = #{OddSockets.get_state(publisher)}"
    )

    # Subscriber joins with presence enabled; forward every message to us so we
    # can match on the nonce.
    inbox = OddSockets.channel(subscriber, channel_name)

    :ok =
      OddSockets.Channel.subscribe(
        inbox,
        fn message -> send(parent, {:demo_message, message}) end,
        %{enable_presence: true}
      )

    IO.puts("[alice] subscribed to #{channel_name} (presence on)")

    # Publisher sends from its OWN connection.
    outbox = OddSockets.channel(publisher, channel_name)

    {:ok, ack} =
      OddSockets.Channel.publish(outbox, %{
        "text" => "hello from bob",
        "nonce" => nonce,
        "from" => "bob"
      })

    IO.puts("[bob] published, messageId = #{ack["message_id"]}")

    # Wait for the cross-client delivery.
    await_round_trip(nonce)

    # Inspect presence, then tear down cleanly.
    {:ok, presence} = OddSockets.Channel.get_presence(inbox)
    IO.puts("[alice] presence: #{presence["count"]} user(s).")

    :ok = OddSockets.Channel.unsubscribe(inbox)
    IO.puts("[alice] unsubscribed.")

    OddSockets.disconnect(subscriber)
    OddSockets.disconnect(publisher)

    IO.puts("\nOK - cross-client round-trip verified")
    System.halt(0)
  end

  # Waits for bob's message to reach alice, matched by nonce.
  defp await_round_trip(nonce) do
    receive do
      {:demo_message, message} ->
        if own_message?(message, nonce) do
          IO.puts("[alice] received bob's message (nonce matched) - real round-trip.")
          :ok
        else
          await_round_trip(nonce)
        end
    after
      @timeout_ms ->
        IO.puts("FAILED - timed out after #{div(@timeout_ms, 1000)}s waiting for round-trip")
        System.halt(1)
    end
  end

  # Messages arrive with string keys; the nonce may sit at the top level or be
  # nested under "message"/"data".
  defp own_message?(%{"nonce" => value}, nonce), do: value == nonce
  defp own_message?(%{"message" => inner}, nonce) when is_map(inner), do: own_message?(inner, nonce)
  defp own_message?(%{"data" => inner}, nonce) when is_map(inner), do: own_message?(inner, nonce)
  defp own_message?(_other, _nonce), do: false

  defp worker_id(client) do
    case OddSockets.get_worker_info(client) do
      %{worker_id: id} -> id
      _ -> "unknown"
    end
  end

  defp get_api_key! do
    case System.get_env("ODDSOCKETS_API_KEY") do
      nil ->
        print_signup_instructions()
        System.halt(1)

      "" ->
        IO.puts("ODDSOCKETS_API_KEY is empty. Set it to your API key and try again.")
        System.halt(1)

      api_key ->
        api_key
    end
  end

  defp print_signup_instructions do
    IO.puts("ODDSOCKETS_API_KEY is not set.")
    IO.puts("")
    IO.puts("Get a free API key (no card required):")
    IO.puts("  1. curl -X POST https://oddsockets.com/api/agent-signup \\")
    IO.puts("       -H \"Content-Type: application/json\" \\")
    IO.puts("       -d '{\"email\":\"you@example.com\",\"agentName\":\"my-agent\",\"platform\":\"elixir\"}'")
    IO.puts("  2. curl -X POST https://oddsockets.com/api/agent-signup/verify \\")
    IO.puts("       -H \"Content-Type: application/json\" \\")
    IO.puts("       -d '{\"email\":\"you@example.com\",\"code\":\"123456\",\"agentName\":\"my-agent\"}'")
    IO.puts("")
    IO.puts("Then: export ODDSOCKETS_API_KEY=\"your-api-key\"")
  end
end
