defmodule OddSockets.Types do
  @moduledoc """
  Type definitions for the OddSockets SDK.
  """

  @type bulk_message :: %{
          channel: String.t(),
          message: term(),
          options: map()
        }

  @type publish_result :: %{
          success: boolean(),
          result: map() | nil,
          error: String.t() | nil
        }

  @type connection_state :: :disconnected | :connecting | :connected | :reconnecting

  @type worker_info :: %{
          worker_id: String.t(),
          worker_url: String.t()
        }

  @type session_info :: %{
          session_id: String.t() | nil,
          client_identifier: String.t(),
          worker_id: String.t() | nil,
          created_at: String.t() | nil
        }

  @type reconnect_info :: %{
          attempt: non_neg_integer(),
          max_attempts: non_neg_integer(),
          delay: non_neg_integer()
        }

  @type worker_assignment :: %{
          url: String.t(),
          worker_id: String.t(),
          session: session_info() | nil,
          client_identifier: String.t(),
          manager_url: String.t()
        }

  @type presence_occupant :: %{
          user_id: String.t(),
          state: map() | nil,
          joined_at: String.t() | nil
        }

  @type presence_info :: %{
          channel: String.t(),
          occupants: [presence_occupant()],
          count: non_neg_integer()
        }

  @type message_data :: %{
          type: String.t(),
          channel: String.t(),
          message: term(),
          timestamp: String.t(),
          message_id: String.t() | nil,
          user_id: String.t() | nil,
          metadata: map() | nil
        }

  @type history_options :: %{
          count: non_neg_integer(),
          start: String.t() | nil,
          end: String.t() | nil
        }

  @type subscription_options :: %{
          max_history: non_neg_integer(),
          retain_history: boolean(),
          enable_presence: boolean()
        }

  @type publish_options :: %{
          ttl: non_neg_integer() | nil,
          metadata: map() | nil
        }

  @type client_event ::
          :connecting
          | :connected
          | :disconnected
          | {:error, term()}
          | {:reconnecting, reconnect_info()}
          | {:worker_assigned, worker_assignment()}
          | :max_reconnect_attempts_reached
