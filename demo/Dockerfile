# Builds the OddSockets Elixir SDK straight from the repo and runs the
# two-client round-trip demo against the LIVE platform. Compilation happens at
# image-build time, so a broken SDK fails the build - only a genuinely-compiling
# SDK produces a runnable image.
#
#   docker build -f demo/Dockerfile -t oddsockets-elixir-demo .
#   docker run --rm -e ODDSOCKETS_API_KEY=ak_your_key_here oddsockets-elixir-demo
FROM elixir:1.16-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=dev

WORKDIR /app
# Copy the whole SDK repo so the demo's path dependency (../) resolves.
COPY . .

WORKDIR /app/demo
RUN mix deps.get && mix compile

CMD ["mix", "run", "-e", "OddSocketsDemo.run()"]
