defmodule OddSockets.ManagerDiscovery do
  @moduledoc """
  Simple Manager Discovery Service

  Always connects to the main manager endpoint which handles
  all routing and load balancing transparently.
  """

  @manager_url "https://connect.oddsockets.tyga.network"

  @doc """
  Get the manager URL (always returns the main endpoint).

  ## Parameters

    * `api_key` - The OddSockets API key (not used, kept for compatibility)

  ## Returns

  The manager URL as a string.

  ## Examples

      iex> OddSockets.ManagerDiscovery.discover_manager_url("your-api-key")
      "https://connect.oddsockets.tyga.network"

  """
  @spec discover_manager_url(String.t()) :: String.t()
  def discover_manager_url(_api_key) do
    @manager_url
  end

  @doc """
  Clear cache (no-op, kept for compatibility).

  In the simplified version, there's no cache to clear.
  """
  @spec clear_cache() :: :ok
  def clear_cache do
    # No cache to clear in simplified version
    :ok
  end

  @doc """
  Get the default manager URL.
  """
  @spec get_manager_url() :: String.t()
  def get_manager_url do
    @manager_url
  end
end
