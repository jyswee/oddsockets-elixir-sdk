# OddSockets Elixir SDK - Demo

A tiny, runnable program that proves a real real-time round-trip against OddSockets
using **two independent clients**: **connect -> subscribe -> publish -> receive**.

Because the subscriber (`alice`) and the publisher (`bob`) are separate connections,
a message that reaches the subscriber can only have travelled through the OddSockets
worker - so this doubles as an honest end-to-end regression test (no mocks, no local
echo). The SDK speaks genuine Socket.IO (Engine.IO v4) over a WebSocket to the
assigned worker, exactly like the JavaScript and Python SDKs.

## Proof it's real

`demo/PROOF.txt` is a captured transcript of this demo running in Docker against the
live platform. Reproduce it yourself in one command (see below) - here is a real run:

```
[connect] connecting both clients...
[alice] worker w002-oddsockets-1
[bob]   worker w002-oddsockets-1
[connect] alice = connected, bob = connected
[alice] subscribed to demo-610597 (presence on)
[bob] published, messageId = 36401ebb-c78a-4617-aa0c-1cf45cdfc403
[alice] received bob's message (nonce matched) - real round-trip.
[alice] presence: 1 user(s).
[alice] unsubscribed.

OK - cross-client round-trip verified
```

## 1. Get a free API key

Two-step email verification (no card required):

```bash
# Step 1 - request a code
curl -X POST https://oddsockets.com/api/agent-signup \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","agentName":"demo","platform":"elixir"}'

# Step 2 - verify and receive your apiKey
curl -X POST https://oddsockets.com/api/agent-signup/verify \
  -H "Content-Type: application/json" \
  -d '{"email":"you@example.com","code":"123456","agentName":"demo"}'
```

The verify response contains your `apiKey` (starts with `ak_`).

## 2. Run it in Docker (recommended)

No local Elixir toolchain needed. Build from the repo root so the SDK source is in
context (the demo uses a Mix path dependency - `{:oddsockets, path: ".."}` - to
compile the SDK straight from the parent, without publishing anything):

```bash
docker build -f demo/Dockerfile -t oddsockets-elixir-demo .
docker run --rm -e ODDSOCKETS_API_KEY="ak_your_key_here" oddsockets-elixir-demo
```

Compilation happens at image-build time, so a broken SDK fails the build - only a
genuinely-compiling SDK produces a runnable image. A successful run prints
`OK - cross-client round-trip verified` and exits `0`.

## 2b. Run it locally with Mix

Requires Elixir 1.14+. The path dependency resolves the SDK from the parent
directory, so the demo is clone-and-run:

```bash
cd demo
mix deps.get
export ODDSOCKETS_API_KEY="ak_your_key_here"
mix run -e "OddSocketsDemo.run()"
```

The key is read from `ODDSOCKETS_API_KEY` and never hardcoded; if it is missing the
program prints the signup instructions above and exits non-zero.

## The code, step by step

Create two clients - a subscriber and a publisher - each on its own connection:

```elixir
{:ok, subscriber} = OddSockets.start_link(api_key: api_key, user_id: "alice", auto_connect: false)
{:ok, publisher}  = OddSockets.start_link(api_key: api_key, user_id: "bob",   auto_connect: false)

:ok = OddSockets.connect(subscriber)
:ok = OddSockets.connect(publisher)
```

Subscribe on the subscriber (presence enabled):

```elixir
inbox = OddSockets.channel(subscriber, "my-channel")

:ok = OddSockets.Channel.subscribe(inbox, fn message ->
  IO.inspect(message["data"], label: "received")
end, %{enable_presence: true})
```

Publish from the *other* client - this is what makes the test honest:

```elixir
outbox = OddSockets.channel(publisher, "my-channel")
{:ok, ack} = OddSockets.Channel.publish(outbox, %{"text" => "hello from bob", "nonce" => nonce})
IO.puts("messageId = #{ack["message_id"]}")
```

Inspect presence, then tear down cleanly:

```elixir
{:ok, presence} = OddSockets.Channel.get_presence(inbox)
IO.puts("count: #{presence["count"]}")
:ok = OddSockets.Channel.unsubscribe(inbox)
OddSockets.disconnect(subscriber)
OddSockets.disconnect(publisher)
```

## What it demonstrates

- Manager discovery + automatic worker assignment (fully transparent)
- `OddSockets.channel/2` -> `Channel.subscribe/3` -> `Channel.publish/3`
- **Cross-client delivery**: a message published by `bob` is delivered to `alice`'s
  subscription in real time - provably through the worker, not a local echo
- Presence tracking, unsubscribe, and graceful disconnect
- A 15-second timeout so a stalled round-trip is reported as a failure (non-zero exit)

## Files

- `Dockerfile` - builds the SDK from source and runs the two-client demo on `elixir:1.16-slim`.
- `PROOF.txt` - captured transcript of a real containerised run against the platform.
- `lib/demo.ex` - the two-client round-trip program.
- `mix.exs` - resolves the SDK via a Mix path dependency (`path: ".."`).
