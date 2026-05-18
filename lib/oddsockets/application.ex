defmodule OddSockets.Application do
  @moduledoc """
  Application module for the OddSockets SDK.
  
  This module starts the application supervision tree.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Add any supervised processes here if needed
      # For now, the SDK doesn't require any global processes
    ]

    opts = [strategy: :one_for_one, name: OddSockets.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
