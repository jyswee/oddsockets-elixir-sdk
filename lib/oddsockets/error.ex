defmodule OddSockets.Error do
  @moduledoc """
  Exception module for OddSockets SDK errors.
  """

  defexception [:message]

  @type t :: %__MODULE__{message: String.t()}

  @doc """
  Create a new OddSockets error with the given message.
  """
  def exception(message) when is_binary(message) do
    %__MODULE__{message: message}
  end

  def exception(opts) when is_list(opts) do
    message = Keyword.get(opts, :message, "OddSockets error")
    %__MODULE__{message: message}
  end
end
