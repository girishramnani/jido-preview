defmodule Jido.Operation.Error do
  @moduledoc """
  Defines error structures and helper functions for Jido Operations.

  This module provides a standardized way to create and handle errors within the Jido system.
  It offers a set of predefined error types and functions to create, manipulate, and convert
  error structures consistently across the application.

  > Why not use Exceptions?
  >
  > Jido Operations and Thunks are designed to be monadic, strictly adhering to the use of result tuples.
  > This approach provides several benefits:
  >
  > 1. Consistent error handling: By using `{:ok, result}` or `{:error, reason}` tuples,
  >    we ensure a uniform way of handling success and failure cases throughout the system.
  >
  > 2. Composability: Monadic operations can be easily chained together, allowing for
  >    cleaner and more maintainable code.
  >
  > 3. Explicit error paths: The use of result tuples makes error cases explicit,
  >    reducing the likelihood of unhandled errors.
  >
  > 4. No silent failures: Unlike exceptions, which can be silently caught and ignored,
  >    result tuples require explicit handling of both success and error cases.
  >
  > 5. Better testability: Monadic operations are easier to test, as both success and
  >    error paths can be explicitly verified.
  >
  > By using this approach instead of exceptions, we gain more control over the flow of our
  > operations and ensure that errors are handled consistently across the entire system.

  ## Usage

  Use this module to create specific error types when exceptions occur in your Jido operations.
  This allows for consistent error handling and reporting throughout the system.

  Example:

      defmodule MyOperation do
        alias Jido.Operation.Error

        def run(params) do
          case validate(params) do
            :ok -> perform_operation(params)
            {:error, reason} -> Error.validation_error("Invalid parameters")
          end
        end
      end
  """

  @typedoc """
  Defines the possible error types in the Jido system.

  - `:invalid_thunk`: Used when a thunk is improperly defined or used.
  - `:bad_request`: Indicates an invalid request from the client.
  - `:validation_error`: Used when input validation fails.
  - `:config_error`: Indicates a configuration issue.
  - `:execution_error`: Used when an error occurs during operation execution.
  - `:operation_error`: General operation-related errors.
  - `:internal_server_error`: Indicates an unexpected internal error.
  - `:timeout`: Used when an operation exceeds its time limit.
  - `:invalid_async_ref`: Indicates an invalid asynchronous operation reference.
  """
  @type error_type ::
          :invalid_thunk
          | :bad_request
          | :validation_error
          | :config_error
          | :execution_error
          | :operation_error
          | :internal_server_error
          | :timeout
          | :invalid_async_ref

  @enforce_keys [:type, :message]
  defstruct [:type, :message, :details, :stacktrace]

  @typedoc """
  Represents a structured error in the Jido system.

  Fields:
  - `type`: The category of the error (see `t:error_type/0`).
  - `message`: A human-readable description of the error.
  - `details`: Optional map containing additional error context.
  - `stacktrace`: Optional list representing the error's stacktrace.
  """
  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          details: map() | nil,
          stacktrace: list() | nil
        }

  @doc """
  Creates a new error struct with the given type and message.

  This is a low-level function used by other error creation functions in this module.
  Consider using the specific error creation functions unless you need fine-grained control.

  ## Parameters
  - `type`: The error type (see `t:error_type/0`).
  - `message`: A string describing the error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Examples

      iex> Jido.Operation.Error.new(:config_error, "Invalid configuration")
      %Jido.Operation.Error{
        type: :config_error,
        message: "Invalid configuration",
        details: nil,
        stacktrace: [...]
      }

      iex> Jido.Operation.Error.new(:execution_error, "Operation failed", %{step: "data_processing"})
      %Jido.Operation.Error{
        type: :execution_error,
        message: "Operation failed",
        details: %{step: "data_processing"},
        stacktrace: [...]
      }
  """
  @spec new(error_type(), String.t(), map() | nil, list() | nil) :: t()
  def new(type, message, details \\ nil, stacktrace \\ nil) do
    %__MODULE__{
      type: type,
      message: message,
      details: details,
      stacktrace: stacktrace || capture_stacktrace()
    }
  end

  @doc """
  Creates a new invalid thunk error.

  Use this when a thunk is improperly defined or used within the Jido system.

  ## Parameters
  - `message`: A string describing the error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Operation.Error.invalid_thunk("Thunk 'MyThunk' is missing required callback")
      %Jido.Operation.Error{
        type: :invalid_thunk,
        message: "Thunk 'MyThunk' is missing required callback",
        details: nil,
        stacktrace: [...]
      }
  """
  @spec invalid_thunk(String.t(), map() | nil, list() | nil) :: t()
  def invalid_thunk(message, details \\ nil, stacktrace \\ nil) do
    new(:invalid_thunk, message, details, stacktrace)
  end

  @doc """
  Creates a new bad request error.

  Use this when the client sends an invalid or malformed request.

  ## Parameters
  - `message`: A string describing the error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Operation.Error.bad_request("Missing required parameter 'user_id'")
      %Jido.Operation.Error{
        type: :bad_request,
        message: "Missing required parameter 'user_id'",
        details: nil,
        stacktrace: [...]
      }
  """
  @spec bad_request(String.t(), map() | nil, list() | nil) :: t()
  def bad_request(message, details \\ nil, stacktrace \\ nil) do
    new(:bad_request, message, details, stacktrace)
  end

  @doc """
  Creates a new validation error.

  Use this when input validation fails for an operation.

  ## Parameters
  - `message`: A string describing the validation error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Operation.Error.validation_error("Invalid email format", %{field: "email", value: "not-an-email"})
      %Jido.Operation.Error{
        type: :validation_error,
        message: "Invalid email format",
        details: %{field: "email", value: "not-an-email"},
        stacktrace: [...]
      }
  """
  @spec validation_error(String.t(), map() | nil, list() | nil) :: t()
  def validation_error(message, details \\ nil, stacktrace \\ nil) do
    new(:validation_error, message, details, stacktrace)
  end

  @doc """
  Creates a new config error.

  Use this when there's an issue with the system or operation configuration.

  ## Parameters
  - `message`: A string describing the configuration error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Operation.Error.config_error("Invalid database connection string")
      %Jido.Operation.Error{
        type: :config_error,
        message: "Invalid database connection string",
        details: nil,
        stacktrace: [...]
      }
  """
  @spec config_error(String.t(), map() | nil, list() | nil) :: t()
  def config_error(message, details \\ nil, stacktrace \\ nil) do
    new(:config_error, message, details, stacktrace)
  end

  @doc """
  Creates a new execution error.

  Use this when an error occurs during the execution of an operation.

  ## Parameters
  - `message`: A string describing the execution error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Operation.Error.execution_error("Failed to process data", %{step: "data_transformation"})
      %Jido.Operation.Error{
        type: :execution_error,
        message: "Failed to process data",
        details: %{step: "data_transformation"},
        stacktrace: [...]
      }
  """
  @spec execution_error(String.t(), map() | nil, list() | nil) :: t()
  def execution_error(message, details \\ nil, stacktrace \\ nil) do
    new(:execution_error, message, details, stacktrace)
  end

  @doc """
  Creates a new operation error.

  Use this for general operation-related errors that don't fit into other categories.

  ## Parameters
  - `message`: A string describing the operation error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Operation.Error.operation_error("Operation 'ProcessOrder' failed", %{order_id: 12345})
      %Jido.Operation.Error{
        type: :operation_error,
        message: "Operation 'ProcessOrder' failed",
        details: %{order_id: 12345},
        stacktrace: [...]
      }
  """
  @spec operation_error(String.t(), map() | nil, list() | nil) :: t()
  def operation_error(message, details \\ nil, stacktrace \\ nil) do
    new(:operation_error, message, details, stacktrace)
  end

  @doc """
  Creates a new internal server error.

  Use this for unexpected errors that occur within the system.

  ## Parameters
  - `message`: A string describing the internal server error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Operation.Error.internal_server_error("Unexpected error in data processing")
      %Jido.Operation.Error{
        type: :internal_server_error,
        message: "Unexpected error in data processing",
        details: nil,
        stacktrace: [...]
      }
  """
  @spec internal_server_error(String.t(), map() | nil, list() | nil) :: t()
  def internal_server_error(message, details \\ nil, stacktrace \\ nil) do
    new(:internal_server_error, message, details, stacktrace)
  end

  @doc """
  Creates a new timeout error.

  Use this when an operation exceeds its allocated time limit.

  ## Parameters
  - `message`: A string describing the timeout error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Operation.Error.timeout("Operation timed out after 30 seconds", %{operation: "FetchUserData"})
      %Jido.Operation.Error{
        type: :timeout,
        message: "Operation timed out after 30 seconds",
        details: %{operation: "FetchUserData"},
        stacktrace: [...]
      }
  """
  @spec timeout(String.t(), map() | nil, list() | nil) :: t()
  def timeout(message, details \\ nil, stacktrace \\ nil) do
    new(:timeout, message, details, stacktrace)
  end

  @doc """
  Creates a new invalid async ref error.

  Use this when an invalid reference to an asynchronous operation is encountered.

  ## Parameters
  - `message`: A string describing the invalid async ref error.
  - `details`: (optional) A map containing additional error details.
  - `stacktrace`: (optional) The stacktrace at the point of error.

  ## Example

      iex> Jido.Operation.Error.invalid_async_ref("Invalid or expired async operation reference")
      %Jido.Operation.Error{
        type: :invalid_async_ref,
        message: "Invalid or expired async operation reference",
        details: nil,
        stacktrace: [...]
      }
  """
  @spec invalid_async_ref(String.t(), map() | nil, list() | nil) :: t()
  def invalid_async_ref(message, details \\ nil, stacktrace \\ nil) do
    new(:invalid_async_ref, message, details, stacktrace)
  end

  @doc """
  Converts the error struct to a plain map.

  This function transforms the error struct into a plain map,
  including the error type and stacktrace if available. It's useful
  for serialization or when working with APIs that expect plain maps.

  ## Parameters
  - `error`: An error struct of type `t:t/0`.

  ## Returns
  A map representation of the error.

  ## Example

      iex> error = Jido.Operation.Error.validation_error("Invalid input")
      iex> Jido.Operation.Error.to_map(error)
      %{
        type: :validation_error,
        message: "Invalid input",
        stacktrace: [...]
      }
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = error) do
    error
    |> Map.from_struct()
    |> Enum.reject(fn {_, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Captures the current stacktrace.

  This function is useful when you want to capture the stacktrace at a specific point
  in your code, rather than at the point where the error is created. It drops the first
  two entries from the stacktrace to remove internal function calls related to this module.

  ## Returns
  The current stacktrace as a list.

  ## Example

      iex> stacktrace = Jido.Operation.Error.capture_stacktrace()
      iex> is_list(stacktrace)
      true
  """
  @spec capture_stacktrace() :: list()
  def capture_stacktrace do
    {:current_stacktrace, stacktrace} = Process.info(self(), :current_stacktrace)
    Enum.drop(stacktrace, 2)
  end
end
