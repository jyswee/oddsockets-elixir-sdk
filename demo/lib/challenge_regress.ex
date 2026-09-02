defmodule OddSocketsChallengeRegress do
  @moduledoc """
  Honest two-client challenge/leaderboard/achievement/invite regression for the
  OddSockets Elixir SDK, run against a live worker via the manager LB.

  Two independent connections share ONE apiKey (owner scope) but use DISTINCT
  userIds (alice + bob). Both subscribe to 'lobby'. Every cross-client
  assertion checks that an event fired by one client surfaces on the OTHER
  client's public event stream (subscribe_events/1) - it can only have arrived
  through the worker, so there is no local echo.

  Run: mix run -e "OddSocketsChallengeRegress.run()"
  """

  alias OddSockets.EnhancedFeatures, as: EF

  @timeout_ms 15_000
  @channel "lobby"

  def run do
    api_key = get_api_key!()
    manager_url = System.get_env("ODDSOCKETS_MANAGER_URL")

    challenge_id = "chal-" <> rand()
    achievement_id = "ach-" <> rand()

    # userIds are overridable so we can force alice/bob onto DIFFERENT workers
    # (proving cross-worker fan-out via the shared Redis adapter) while keeping
    # identical shared-key owner scope. Defaults stay alice/bob.
    alice_id = System.get_env("ALICE_ID") || "alice"
    bob_id = System.get_env("BOB_ID") || "bob"

    results = :ets.new(:results, [:public, :ordered_set])
    n = fn -> :ets.info(results, :size) end
    pass = fn label -> :ets.insert(results, {n.(), :pass, label}); IO.puts("  PASS  #{label}") end
    fail = fn label, detail -> :ets.insert(results, {n.(), :fail, label}); IO.puts("  FAIL  #{label} :: #{inspect(detail)}") end

    IO.puts("[connect] connecting alice + bob (shared key, distinct userId)...")

    common = [api_key: api_key, auto_connect: false]
    common = if manager_url, do: Keyword.put(common, :manager_url, manager_url), else: common

    {:ok, alice} = OddSockets.start_link(Keyword.merge(common, user_id: alice_id))
    {:ok, bob} = OddSockets.start_link(Keyword.merge(common, user_id: bob_id))

    :ok = OddSockets.connect(alice)
    :ok = OddSockets.connect(bob)

    # Route each client's public event stream to a dedicated collector so we can
    # assert on WHO saw WHAT (cross-client isolation).
    alice_events = start_collector()
    bob_events = start_collector()
    :ok = route_events(alice, alice_events)
    :ok = route_events(bob, bob_events)

    aw = worker_id(alice)
    bw = worker_id(bob)
    IO.puts("[alice] worker #{aw}  state=#{OddSockets.get_state(alice)}")
    IO.puts("[bob]   worker #{bw}  state=#{OddSockets.get_state(bob)}")
    IO.puts("[workers] alice=#{aw} bob=#{bw} #{if aw != bw, do: "(CROSS-WORKER)", else: "(same worker)"}")

    # Both join 'lobby' so room broadcasts reach both.
    _ = OddSockets.channel(alice, @channel)
    _ = OddSockets.channel(bob, @channel)
    ach = OddSockets.channel(alice, @channel)
    bch = OddSockets.channel(bob, @channel)
    :ok = OddSockets.Channel.subscribe(ach, fn _ -> :ok end, %{enable_presence: true})
    :ok = OddSockets.Channel.subscribe(bch, fn _ -> :ok end, %{enable_presence: true})
    Process.sleep(700)

    # ---------- 1. create_challenge (ack) ----------
    case EF.create_challenge(alice, %{
           challengeId: challenge_id,
           metric: "score",
           ranked: true,
           channel: @channel
         }) do
      {:ok, _ack} -> pass.("1 create_challenge acked challenge_create_success")
      other -> fail.("1 create_challenge ack", other)
    end

    # ---------- 2. report_progress => alice sees challenge_progress + leaderboard_rank_change ----------
    clear(alice_events)
    clear(bob_events)
    :ok = EF.report_progress(alice, %{challengeId: challenge_id, metric: "score", value: 40, eventId: "ev-a-" <> rand()})
    :ok = EF.report_progress(bob, %{challengeId: challenge_id, metric: "score", value: 55, eventId: "ev-b-" <> rand()})

    prog = await(alice_events, "challenge_progress", fn p -> cid(p) == challenge_id end)
    case prog do
      {:ok, _} -> pass.("2 alice saw challenge_progress (room broadcast)")
      :timeout -> fail.("2 challenge_progress", :timeout)
    end

    rank = await(alice_events, "leaderboard_rank_change", fn p -> cid(p) == challenge_id end)
    case rank do
      {:ok, _} -> pass.("2 alice saw leaderboard_rank_change (ranked)")
      :timeout -> fail.("2 leaderboard_rank_change", :timeout)
    end

    # ---------- 3. get_standings: bob@55 rank1, alice@40 rank2, alice yourRank=2 ----------
    Process.sleep(400)
    case EF.get_standings(alice, %{challengeId: challenge_id, limit: 10}) do
      {:ok, ack} ->
        standings = dig(ack, "standings") || []
        your = dig(ack, "yourRank")
        r1 = Enum.find(standings, &(rankof(&1) == 1))
        r2 = Enum.find(standings, &(rankof(&1) == 2))
        ok =
          r1 && valof(r1) == 55 && r2 && valof(r2) == 40 && your == 2
        if ok do
          pass.("3 standings bob@55 rank1 / alice@40 rank2 / alice yourRank=2")
        else
          fail.("3 standings shape", %{standings: standings, yourRank: your})
        end

      other ->
        fail.("3 get_standings ack", other)
    end

    # ---------- 4. complete: alice tied => finalValue40 rank2; bob conceded => finalValue55 rank1 ----------
    case EF.complete_challenge(alice, %{challengeId: challenge_id, outcome: "tied", eventId: "ev-ac-" <> rand()}) do
      {:ok, ack} ->
        if dig(ack, "outcome") == "tied" && numeq(dig(ack, "finalValue"), 40) && dig(ack, "rank") == 2,
          do: pass.("4 alice complete(tied) finalValue40 rank2"),
          else: fail.("4 alice complete", ack)

      other ->
        fail.("4 alice complete ack", other)
    end

    case EF.complete_challenge(bob, %{challengeId: challenge_id, outcome: "conceded", eventId: "ev-bc-" <> rand()}) do
      {:ok, ack} ->
        if dig(ack, "outcome") == "conceded" && numeq(dig(ack, "finalValue"), 55) && dig(ack, "rank") == 1,
          do: pass.("4 bob complete(conceded) finalValue55 rank1"),
          else: fail.("4 bob complete", ack)

      other ->
        fail.("4 bob complete ack", other)
    end

    # ---------- 5. alice unlock(50) => bob sees achievement_progress in_progress ----------
    clear(bob_events)
    :ok = EF.unlock_achievement(alice, %{achievementId: achievement_id, name: "Century", percentComplete: 50, channel: @channel})

    case await(bob_events, "achievement_progress", fn p -> aid(p) == achievement_id end) do
      {:ok, p} ->
        st = dig(datao(p), "status") || dig(p, "status")
        if st == "in_progress",
          do: pass.("5 bob saw achievement_progress in_progress (<100, no banner)"),
          else: fail.("5 achievement_progress status", st)

      :timeout ->
        fail.("5 achievement_progress", :timeout)
    end

    # It must NOT be an unlock banner at 50%.
    case await(bob_events, "achievement_unlock", fn p -> aid(p) == achievement_id end, 1500) do
      {:ok, _} -> fail.("5 no premature achievement_unlock at 50%", :got_unlock)
      :timeout -> pass.("5 no premature achievement_unlock banner at 50%")
    end

    # ---------- 6/7 achievement complete + query ----------
    clear(bob_events)
    :ok = EF.unlock_achievement(alice, %{achievementId: achievement_id, name: "Century", percentComplete: 100, channel: @channel})

    case await(bob_events, "achievement_unlock", fn p -> aid(p) == achievement_id end) do
      {:ok, p} ->
        st = dig(datao(p), "status") || dig(p, "status")
        if st in ["unlocked", nil],
          do: pass.("6 bob saw achievement_unlock (>=100 unlocked)"),
          else: fail.("6 achievement_unlock status", st)

      :timeout ->
        fail.("6 achievement_unlock", :timeout)
    end

    Process.sleep(400)
    case EF.get_achievements(alice, %{achievementId: achievement_id}) do
      {:ok, ack} ->
        achs = dig(ack, "achievements") || []
        a = Enum.find(achs, fn x -> dig(x, "achievementId") == achievement_id end)
        if a && numeq(dig(a, "percentComplete"), 100) && dig(a, "status") == "unlocked",
          do: pass.("7 get_achievements 100/unlocked"),
          else: fail.("7 get_achievements", achs)

      other ->
        fail.("7 get_achievements ack", other)
    end

    # ---------- 8. alice invite bob => bob sees challenge_invited (FLAT, from alice), alice not own ----------
    clear(bob_events)
    clear(alice_events)
    invite_id =
      case EF.send_challenge_invite(alice, %{toUserId: bob_id, type: "match", payload: %{"mode" => "duel"}, ttl: 300}) do
        {:ok, ack} ->
          iid = dig(ack, "inviteId")
          if dig(ack, "toUserId") == bob_id && dig(ack, "status") == "pending" && iid,
            do: pass.("8 send_challenge_invite acked (inviteId/toUserId/pending)"),
            else: fail.("8 invite ack shape", ack)
          iid

        other ->
          fail.("8 send_challenge_invite ack", other)
          nil
      end

    case await(bob_events, "challenge_invited", fn p -> dig(p, "inviteId") == invite_id or dig(p, "from") == alice_id end) do
      {:ok, p} ->
        payload = dig(p, "payload") || %{}
        if dig(payload, "mode") == "duel",
          do: pass.("8 bob (invitee) saw challenge_invited payload from alice (FLAT)"),
          else: fail.("8 challenge_invited payload", p)

      :timeout ->
        fail.("8 challenge_invited to bob", :timeout)
    end

    case await(alice_events, "challenge_invited", fn p -> dig(p, "inviteId") == invite_id end, 1500) do
      {:ok, _} -> fail.("8 inviter must NOT receive own invite", :alice_got_own)
      :timeout -> pass.("8 alice did not receive her own invite")
    end

    # ---------- 9 bob lists invites ----------
    case EF.get_challenge_invites(bob) do
      {:ok, ack} ->
        invites = dig(ack, "invites") || []
        if Enum.any?(invites, fn i -> dig(i, "inviteId") == invite_id end),
          do: pass.("9 bob get_challenge_invites lists the invite"),
          else: fail.("9 get_challenge_invites", invites)

      other ->
        fail.("9 get_challenge_invites ack", other)
    end

    # ---------- 10 bob reply(accept) => alice sees challenge_reply_received (FLAT) ----------
    clear(alice_events)
    case EF.reply_challenge_invite(bob, %{inviteId: invite_id, accept: true}) do
      {:ok, _} -> pass.("10 reply_challenge_invite acked")
      other -> fail.("10 reply ack", other)
    end

    case await(alice_events, "challenge_reply_received", fn p -> dig(p, "inviteId") == invite_id end) do
      {:ok, p} ->
        acc = dig(p, "accept")
        if acc in [true, "true", nil],
          do: pass.("10 alice (inviter) saw challenge_reply_received (FLAT)"),
          else: fail.("10 challenge_reply_received accept", p)

      :timeout ->
        fail.("10 challenge_reply_received to alice", :timeout)
    end

    # ---------- 11 fresh invite + cancel => bob sees challenge_invite_cancelled ----------
    clear(bob_events)
    invite2 =
      case EF.send_challenge_invite(alice, %{toUserId: bob_id, type: "match", payload: %{"mode" => "rematch"}, ttl: 300}) do
        {:ok, ack} -> dig(ack, "inviteId")
        _ -> nil
      end

    # let it deliver, then cancel
    _ = await(bob_events, "challenge_invited", fn p -> dig(p, "inviteId") == invite2 end, 4000)
    clear(bob_events)

    case EF.cancel_challenge_invite(alice, %{inviteId: invite2}) do
      {:ok, _} -> pass.("11 cancel_challenge_invite acked")
      other -> fail.("11 cancel ack", other)
    end

    case await(bob_events, "challenge_invite_cancelled", fn p -> dig(p, "inviteId") == invite2 end) do
      {:ok, _} -> pass.("11 bob saw challenge_invite_cancelled (FLAT)")
      :timeout -> fail.("11 challenge_invite_cancelled to bob", :timeout)
    end

    # ---------- teardown + report ----------
    OddSockets.disconnect(alice)
    OddSockets.disconnect(bob)

    all = :ets.tab2list(results) |> Enum.sort()
    fails = Enum.count(all, fn {_, s, _} -> s == :fail end)
    total = length(all)
    IO.puts("\n==== RESULT: #{total - fails}/#{total} assertions passed ====")
    IO.puts("workers: alice=#{aw} bob=#{bw}#{if aw != bw, do: " CROSS-WORKER", else: ""}")

    if fails == 0 do
      IO.puts("OK - challenge lifecycle two-client regression PASSED")
      System.halt(0)
    else
      IO.puts("FAIL - #{fails} assertion(s) failed")
      System.halt(3)
    end
  end

  # ---------- event collector (per-client) ----------

  defp start_collector do
    spawn(fn -> collect([]) end)
  end

  defp collect(events) do
    receive do
      {:ev, event, payload} -> collect([{event, payload} | events])
      {:clear, from} -> send(from, :cleared); collect([])
      {:query, event, matcher, from} ->
        hit = Enum.find(events, fn {e, p} -> e == event and matcher.(p) end)
        send(from, {:query_result, hit})
        collect(events)
    end
  end

  defp route_events(client, collector) do
    parent = self()
    # Bridge: subscribe a relay process to the client's public event stream and
    # forward broadcast events into the collector.
    spawn(fn ->
      OddSockets.subscribe_events(client)
      send(parent, :routed)
      relay(collector)
    end)

    receive do
      :routed -> :ok
    after
      2000 -> :ok
    end
  end

  defp relay(collector) do
    receive do
      {:oddsockets_event, {event, payload}} when is_binary(event) and is_map(payload) ->
        send(collector, {:ev, event, payload})
        relay(collector)

      _other ->
        relay(collector)
    end
  end

  defp clear(collector) do
    send(collector, {:clear, self()})
    receive do
      :cleared -> :ok
    after
      1000 -> :ok
    end
  end

  defp await(collector, event, matcher, timeout \\ @timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout
    poll(collector, event, matcher, deadline)
  end

  defp poll(collector, event, matcher, deadline) do
    send(collector, {:query, event, matcher, self()})

    hit =
      receive do
        {:query_result, h} -> h
      after
        1000 -> nil
      end

    cond do
      hit != nil -> {:ok, elem(hit, 1)}
      System.monotonic_time(:millisecond) >= deadline -> :timeout
      true -> Process.sleep(150); poll(collector, event, matcher, deadline)
    end
  end

  # ---------- envelope helpers ----------

  # Room broadcasts wrap semantic fields under "data"; directed events are flat.
  defp datao(%{"data" => d}) when is_map(d), do: d
  defp datao(p), do: p

  defp cid(p), do: dig(p, "challengeId") || dig(datao(p), "challengeId")
  defp aid(p), do: dig(p, "achievementId") || dig(datao(p), "achievementId")

  defp rankof(m), do: dig(m, "rank")
  defp valof(m), do: num(dig(m, "value"))

  defp dig(m, k) when is_map(m), do: Map.get(m, k) || Map.get(m, to_string(k))
  defp dig(_, _), do: nil

  defp num(n) when is_number(n), do: n
  defp num(n) when is_binary(n) do
    case Float.parse(n) do
      {f, _} -> if f == trunc(f), do: trunc(f), else: f
      :error -> n
    end
  end
  defp num(n), do: n

  defp numeq(a, b), do: num(a) == num(b)

  defp worker_id(client) do
    case OddSockets.get_worker_info(client) do
      %{worker_id: id} -> id
      _ -> "unknown"
    end
  end

  defp rand, do: :crypto.strong_rand_bytes(5) |> Base.encode16(case: :lower)

  defp get_api_key! do
    case System.get_env("ODDSOCKETS_API_KEY") || System.get_env("OS_KEY") do
      nil -> IO.puts("ODDSOCKETS_API_KEY / OS_KEY not set."); System.halt(1)
      "" -> IO.puts("api key empty."); System.halt(1)
      k -> k
    end
  end
end
