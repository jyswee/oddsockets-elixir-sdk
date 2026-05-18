defmodule OddSockets.MessageSizeValidator do
  @moduledoc """
  Message size validation utilities.

  Validates message sizes against industry standard limits (matches PubNub)
  for reliable real-time messaging.
  """

  alias OddSockets.Error

  # Message size limits (industry standard - matches PubNub)
  @max_message_size 32768  # 32KB in bytes
  @max_message_size_kb 32

  @doc """
  Validate message size.

  Raises an `OddSockets.Error` if the message exceeds the size limit.

  ## Parameters

    * `message` - Message to validate (any term)

  ## Returns

  The message size in bytes if valid.

  ## Raises

  `OddSockets.Error` if the message exceeds the maximum allowed size.

  ## Examples

      iex> OddSockets.MessageSizeValidator.validate_message_size("Hello")
      5

      iex> large_message = String.duplicate("x", 40000)
      iex> OddSockets.MessageSizeValidator.validate_message_size(large_message)
      ** (OddSockets.Error) Message size (39KB) exceeds maximum allowed size of 32KB...

  """
  @spec validate_message_size(term()) :: non_neg_integer()
  def validate_message_size(message) do
    message_str = if is_binary(message), do: message, else: Jason.encode!(message)
    message_size = byte_size(message_str)
    
    if message_size > @max_message_size do
      size_kb = Float.round(message_size / 1024, 0) |> trunc()
      
      raise Error, """
      Message size (#{size_kb}KB) exceeds maximum allowed size of #{@max_message_size_kb}KB. \
      This limit matches industry standards (PubNub, Socket.IO) for reliable real-time messaging.
      """
    end
    
    message_size
  end

  @doc """
  Get the maximum message size in bytes.
  """
  @spec max_message_size() :: non_neg_integer()
  def max_message_size, do: @max_message_size

  @doc """
  Get the maximum message size in kilobytes.
  """
  @spec max_message_size_kb() :: non_neg_integer()
  def max_message_size_kb, do: @max_message_size_kb

  @doc """
  Check if a message size is valid without raising an exception.

  ## Parameters

    * `message` - Message to validate (any term)

  ## Returns

  `{:ok, size}` if valid, `{:error, reason}` if invalid.

  ## Examples

      iex> OddSockets.MessageSizeValidator.check_message_size("Hello")
      {:ok, 5}

      iex> large_message = String.duplicate("x", 40000)
      iex> OddSockets.MessageSizeValidator.check_message_size(large_message)
      {:error, "Message size (39KB) exceeds maximum allowed size of 32KB"}

  """
  @spec check_message_size(term()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def check_message_size(message) do
    try do
      size = validate_message_size(message)
      {:ok, size}
    rescue
      e in Error ->
        {:error, e.message}
    end
  end
end
