defmodule OddSockets.ManagerDiscovery do
  @moduledoc """
  Resolves the manager endpoint used for worker assignment.

  A manager pointed at the wrong cluster still answers happily, so silently
  substituting a default would connect a self-hosted or QA deployment to
  production without any visible symptom. The configured value is therefore
  used verbatim, and the default endpoint applies only when nothing has been
  configured at all - never as a recovery path for an unreachable manager.
  """

  @default_manager_url "https://connect.oddsockets.tyga.network"
  @env_var "ODDSOCKETS_MANAGER_URL"

  @doc """
  Resolve the manager URL to use.

  Precedence: the value passed in (from `:manager_url` on the client), then
  `config :oddsockets, manager_url: ...`, then the `ODDSOCKETS_MANAGER_URL`
  environment variable, then the default endpoint.

  ## Parameters

    * `configured` - The manager URL supplied by the caller, or `nil`

  ## Returns

    * `{:ok, url}` with any trailing slashes stripped
    * `{:error, "Invalid managerUrl: <value>"}` if the resolved value is not an
      absolute http(s) URL

  ## Examples

      iex> OddSockets.ManagerDiscovery.discover_manager_url("https://manager.internal/")
      {:ok, "https://manager.internal"}

      iex> OddSockets.ManagerDiscovery.discover_manager_url("not-a-url")
      {:error, "Invalid managerUrl: not-a-url"}

  """
  @spec discover_manager_url(String.t() | nil) :: {:ok, String.t()} | {:error, String.t()}
  def discover_manager_url(configured \\ nil) do
    case first_present([
           configured,
           Application.get_env(:oddsockets, :manager_url),
           System.get_env(@env_var)
         ]) do
      nil -> {:ok, @default_manager_url}
      url -> normalize_url(url)
    end
  end

  @doc """
  Same as `discover_manager_url/1` but raises `ArgumentError` on an invalid URL.

  Used where a misconfiguration should stop the client from starting rather
  than surface later as a connection failure.
  """
  @spec discover_manager_url!(String.t() | nil) :: String.t()
  def discover_manager_url!(configured \\ nil) do
    case discover_manager_url(configured) do
      {:ok, url} -> url
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  The endpoint used when no manager URL has been configured anywhere.
  """
  @spec default_manager_url() :: String.t()
  def default_manager_url, do: @default_manager_url

  defp first_present(candidates) do
    Enum.find_value(candidates, fn
      value when is_binary(value) -> if String.trim(value) == "", do: nil, else: value
      _ -> nil
    end)
  end

  defp normalize_url(url) do
    trimmed = url |> String.trim() |> String.trim_trailing("/")

    case URI.parse(trimmed) do
      %URI{scheme: scheme, host: host}
      when scheme in ["http", "https"] and is_binary(host) and host != "" ->
        {:ok, trimmed}

      _ ->
        {:error, "Invalid managerUrl: #{url}"}
    end
  end
end
