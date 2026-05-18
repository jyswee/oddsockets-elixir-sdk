defmodule OddSockets.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/jyswee/oddsockets-elixir-sdk"

  def project do
    [
      app: :oddsockets,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      homepage_url: "https://docs.oddsockets.com/sdks/elixir",
      name: "OddSockets",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto, :ssl],
      mod: {OddSockets.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # WebSocket client
      {:websocket_client, "~> 1.5"},
      # HTTP client
      {:httpoison, "~> 2.0"},
      # JSON handling
      {:jason, "~> 1.4"},
      # GenServer utilities
      {:gen_stage, "~> 1.2"},
      # Documentation
      {:ex_doc, "~> 0.30", only: :dev, runtime: false},
      # Testing
      {:excoveralls, "~> 0.18", only: :test},
      {:mox, "~> 1.0", only: :test}
    ]
  end

  defp description do
    """
    Official Elixir SDK for OddSockets real-time messaging platform.
    Provides a simple interface for pub/sub messaging with automatic
    manager discovery and worker load balancing.
    """
  end

  defp package do
    [
      name: "oddsockets",
      files: ~w(lib .formatter.exs mix.exs README* LICENSE*),
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Documentation" => "https://docs.oddsockets.com/sdks/elixir",
        "OddSockets Platform" => "https://oddsockets.com"
      },
      maintainers: ["Joe Wee"]
    ]
  end

  defp docs do
    [
      main: "OddSockets",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        "Core": [OddSockets, OddSockets.Channel],
        "Services": [OddSockets.ManagerDiscovery, OddSockets.MessageSizeValidator],
        "Errors": [OddSockets.Error],
        "Types": [OddSockets.Types]
      ]
    ]
  end
end
