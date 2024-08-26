defmodule Jido.Operation.Chain do
  @moduledoc """
  Provides functionality to chain multiple Jido Operations together.

  This module allows for sequential execution of operations, where the output
  of one operation becomes the input for the next operation in the chain.

  ## Chaining Thunks

  Operations can be chained together in various ways:

  1. Simple chain of operation modules:

      ```elixir
      Chain.chain([AddOne, MultiplyByTwo, SubtractThree], %{value: 5})
      ```

  2. Using the tuple syntax for operation-specific options:

      ```elixir
      Chain.chain([
        AddOne,
        {MultiplyBy, [factor: 3]},
        {WriteToFile, [filename: "result.txt"]},
        SubtractThree
      ], %{value: 5})
      ```

  The tuple syntax `{OperationModule, options}` allows you to pass specific options
  to individual operations in the chain. This is useful when an operation requires
  additional configuration beyond the standard input parameters.

  3. Mixing simple and tuple syntax:

      ```elixir
      Chain.chain([
        AddOne,
        MultiplyByTwo,
        {ConditionalOperation, [condition: :greater_than_10]},
        SubtractThree
      ], %{value: 5})
      ```

  This flexibility allows you to create complex operation chains while maintaining
  readability and allowing for operation-specific configurations when needed.
  """

  alias Jido.Operation
  alias Jido.Operation.Error

  require Logger
  require OK

  @type chain_operation :: module() | {module(), keyword()}
  @type chain_result :: {:ok, map()} | {:error, Error.t()} | Task.t()

  @doc """
  Executes a chain of operations sequentially.

  ## Parameters

  - `operations`: A list of operations to be executed in order. Each operation
    can be a module (the operation module) or a tuple of `{operation_module, options}`.
  - `initial_params`: A map of initial parameters to be passed to the first operation.
  - `opts`: Additional options for the chain execution.

  ## Options

  - `:async` - When set to `true`, the chain will be executed asynchronously (default: `false`).
  - `:context` - A map of context data to be passed to each operation.

  ## Returns

  - `{:ok, result}` where `result` is the final output of the chain.
  - `{:error, error}` if any operation in the chain fails.
  - `Task.t()` if the `:async` option is set to `true`.

  ## Examples

      iex> Jido.Operation.Chain.chain([AddOne, MultiplyByTwo], %{value: 5})
      {:ok, %{value: 12}}

      iex> Jido.Operation.Chain.chain([AddOne, {WriteFile, [file_name: "test.txt", content: "Hello"]}, MultiplyByTwo], %{value: 5})
      {:ok, %{value: 12, written_file: "test.txt"}}
  """
  @spec chain([chain_operation()], map(), keyword()) :: chain_result()
  def chain(operations, initial_params \\ %{}, opts \\ []) do
    async = Keyword.get(opts, :async, false)
    context = Keyword.get(opts, :context, %{})
    opts = Keyword.drop(opts, [:async, :context])

    chain_fun = fn ->
      Enum.reduce_while(operations, {:ok, initial_params}, fn
        operation, {:ok, params} when is_atom(operation) ->
          run_operation(operation, params, context, opts)

        {operation, operation_opts}, {:ok, params} when is_atom(operation) and is_list(operation_opts) ->
          merged_params = Map.merge(params, Map.new(operation_opts))
          run_operation(operation, merged_params, context, opts)

        invalid_operation, _ ->
          {:halt, {:error, Error.bad_request("Invalid chain operation", %{operation: invalid_operation})}}
      end)
    end

    if async, do: Task.async(chain_fun), else: chain_fun.()
  end

  defp run_operation(operation, params, context, opts) do
    Logger.debug("Executing operation in chain", %{
      operation: operation,
      params: params,
      context: context
    })

    case Operation.run(operation, params, context, opts) do
      {:ok, result} ->
        {:cont, OK.success(Map.merge(params, result))}

      {:error, %Error{} = error} ->
        Logger.warning("Operation in chain failed", %{
          operation: operation,
          error: error
        })

        {:halt, OK.failure(error)}
    end
  end
end
