defmodule Jido.Operation do
  @moduledoc """
  Provides a robust framework for executing and managing operations (Thunks) in a distributed system.

  This module offers functionality to:
  - Run operations synchronously or asynchronously
  - Manage timeouts and retries
  - Cancel running operations
  - Normalize and validate input parameters and context
  - Emit telemetry events for monitoring and debugging

  Operations are defined as modules (Thunks) that implement specific callbacks, allowing for
  a standardized way of defining and executing complex operations across a distributed system.

  ## Features

  - Synchronous and asynchronous operation execution
  - Automatic retries with exponential backoff
  - Timeout handling for long-running operations
  - Parameter and context normalization
  - Comprehensive error handling and reporting
  - Telemetry integration for monitoring and tracing
  - Cancellation of running operations

  ## Usage

  Operations are executed using the `run/4` or `run_async/4` functions:

      Jido.Operation.run(MyThunk, %{param1: "value"}, %{context_key: "context_value"})

  See `Jido.Operation.Thunk` for how to define a Thunk.

  For asynchronous execution:

      async_ref = Jido.Operation.run_async(MyThunk, params, context)
      # ... do other work ...
      result = Jido.Operation.await(async_ref)

  """
  use Private

  alias Jido.Operation.Error

  require Logger
  require OK

  @default_timeout 5000
  @default_max_retries 1
  @initial_backoff 1000

  @type thunk :: module()
  @type params :: map()
  @type context :: map()
  @type run_opts :: [timeout: non_neg_integer()]
  @type async_ref :: %{ref: reference(), pid: pid()}

  @doc """
  Executes a Thunk synchronously with the given parameters and context.

  ## Parameters

  - `thunk`: The module implementing the Thunk behavior.
  - `params`: A map of input parameters for the Thunk.
  - `context`: A map providing additional context for the Thunk execution.
  - `opts`: Options controlling the execution:
    - `:timeout` - Maximum time (in ms) allowed for the Thunk to complete (default: #{@default_timeout}).
    - `:max_retries` - Maximum number of retry attempts (default: #{@default_max_retries}).
    - `:backoff` - Initial backoff time in milliseconds, doubles with each retry (default: #{@initial_backoff}).

  ## Returns

  - `{:ok, result}` if the Thunk executes successfully.
  - `{:error, reason}` if an error occurs during execution.

  ## Examples

      iex> Jido.Operation.run(MyThunk, %{input: "value"}, %{user_id: 123})
      {:ok, %{result: "processed value"}}

      iex> Jido.Operation.run(MyThunk, %{invalid: "input"}, %{}, timeout: 1000)
      {:error, %Jido.Operation.Error{type: :validation_error, message: "Invalid input"}}

  """
  @spec run(thunk(), params(), context(), run_opts()) :: {:ok, map()} | {:error, Error.t()}
  def run(thunk, params \\ %{}, context \\ %{}, opts \\ [])

  def run(thunk, params, context, opts) when is_atom(thunk) and is_list(opts) do
    with {:ok, normalized_params} <- normalize_params(params),
         {:ok, normalized_context} <- normalize_context(context),
         :ok <- validate_thunk(thunk),
         OK.success(validated_params) <- validate_params(thunk, normalized_params) do
      do_run_with_retry(thunk, validated_params, normalized_context, opts)
    else
      {:error, reason} -> OK.failure(reason)
    end
  rescue
    e in [FunctionClauseError, BadArityError, BadFunctionError] ->
      OK.failure(Error.invalid_thunk("Invalid thunk module: #{Exception.message(e)}"))

    e ->
      OK.failure(Error.internal_server_error("An unexpected error occurred: #{Exception.message(e)}"))
  catch
    kind, reason ->
      OK.failure(Error.internal_server_error("Caught #{kind}: #{inspect(reason)}"))
  end

  def run(thunk, _params, _context, _opts) do
    OK.failure(Error.invalid_thunk("Expected thunk to be a module, got: #{inspect(thunk)}"))
  end

  @doc """
  Executes a Thunk asynchronously with the given parameters and context.

  This function immediately returns a reference that can be used to await the result
  or cancel the operation.

  ## Parameters

  - `thunk`: The module implementing the Thunk behavior.
  - `params`: A map of input parameters for the Thunk.
  - `context`: A map providing additional context for the Thunk execution.
  - `opts`: Options controlling the execution (same as `run/4`).

  ## Returns

  An `async_ref` map containing:
  - `:ref` - A unique reference for this async operation.
  - `:pid` - The PID of the process executing the Thunk.

  ## Examples

      iex> async_ref = Jido.Operation.run_async(MyThunk, %{input: "value"}, %{user_id: 123})
      %{ref: #Reference<0.1234.5678>, pid: #PID<0.234.0>}

      iex> result = Jido.Operation.await(async_ref)
      {:ok, %{result: "processed value"}}

  """
  @spec run_async(thunk(), params(), context(), run_opts()) :: async_ref()
  def run_async(thunk, params \\ %{}, context \\ %{}, opts \\ []) do
    caller = self()
    ref = make_ref()

    {pid, _} =
      spawn_monitor(fn ->
        result = run(thunk, params, context, opts)
        send(caller, {:thunk_async_result, ref, result})
      end)

    %{ref: ref, pid: pid}
  end

  @doc """
  Waits for the result of an asynchronous Thunk execution.

  ## Parameters

  - `async_ref`: The reference returned by `run_async/4`.
  - `timeout`: Maximum time (in ms) to wait for the result (default: 5000).

  ## Returns

  - `{:ok, result}` if the Thunk executes successfully.
  - `{:error, reason}` if an error occurs during execution or if the operation times out.

  ## Examples

      iex> async_ref = Jido.Operation.run_async(MyThunk, %{input: "value"})
      iex> Jido.Operation.await(async_ref, 10_000)
      {:ok, %{result: "processed value"}}

      iex> async_ref = Jido.Operation.run_async(SlowThunk, %{input: "value"})
      iex> Jido.Operation.await(async_ref, 100)
      {:error, %Jido.Operation.Error{type: :timeout, message: "Async operation timed out after 100ms"}}

  """
  @spec await(async_ref(), timeout()) :: {:ok, map()} | {:error, Error.t()}
  def await(%{ref: ref, pid: pid}, timeout \\ 5000) do
    receive do
      {:thunk_async_result, ^ref, result} ->
        result

      {:DOWN, _, :process, ^pid, reason} ->
        {:error, Error.execution_error("Async operation failed: #{inspect(reason)}")}
    after
      timeout ->
        Process.exit(pid, :kill)
        {:error, Error.timeout("Async operation timed out after #{timeout}ms")}
    end
  end

  @doc """
  Cancels a running asynchronous Thunk execution.

  ## Parameters

  - `async_ref`: The reference returned by `run_async/4`, or just the PID of the process to cancel.

  ## Returns

  - `:ok` if the cancellation was successful.
  - `{:error, reason}` if the cancellation failed or the input was invalid.

  ## Examples

      iex> async_ref = Jido.Operation.run_async(LongRunningThunk, %{input: "value"})
      iex> Jido.Operation.cancel(async_ref)
      :ok

      iex> Jido.Operation.cancel("invalid")
      {:error, %Jido.Operation.Error{type: :invalid_async_ref, message: "Invalid async ref for cancellation"}}

  """
  @spec cancel(async_ref() | pid()) :: :ok | {:error, Error.t()}
  def cancel(%{ref: _ref, pid: pid}), do: cancel(pid)
  def cancel(%{pid: pid}), do: cancel(pid)

  def cancel(pid) when is_pid(pid) do
    Process.exit(pid, :shutdown)
    :ok
  end

  def cancel(_), do: {:error, Error.invalid_async_ref("Invalid async ref for cancellation")}

  private do
    @spec normalize_params(params()) :: {:ok, map()} | {:error, Error.t()}
    defp normalize_params(%Error{} = error), do: OK.failure(error)
    defp normalize_params(params) when is_map(params), do: OK.success(params)
    defp normalize_params(params) when is_list(params), do: OK.success(Map.new(params))
    defp normalize_params({:ok, params}) when is_map(params), do: OK.success(params)
    defp normalize_params({:ok, params}) when is_list(params), do: OK.success(Map.new(params))
    defp normalize_params({:error, reason}), do: OK.failure(Error.validation_error(reason))

    defp normalize_params(params), do: OK.failure(Error.validation_error("Invalid params type: #{inspect(params)}"))

    @spec normalize_context(context()) :: {:ok, map()} | {:error, Error.t()}
    defp normalize_context(context) when is_map(context), do: OK.success(context)
    defp normalize_context(context) when is_list(context), do: OK.success(Map.new(context))

    defp normalize_context(context), do: OK.failure(Error.validation_error("Invalid context type: #{inspect(context)}"))

    @spec validate_thunk(thunk()) :: :ok | {:error, Error.t()}
    defp validate_thunk(thunk) do
      case Code.ensure_compiled(thunk) do
        {:module, _} ->
          if function_exported?(thunk, :run, 2) do
            :ok
          else
            {:error, Error.invalid_thunk("Module #{inspect(thunk)} is not a valid thunk: missing run/2 function")}
          end

        {:error, reason} ->
          {:error, Error.invalid_thunk("Failed to compile module #{inspect(thunk)}: #{inspect(reason)}")}
      end
    end

    @spec validate_params(thunk(), map()) :: {:ok, map()} | {:error, Error.t()}
    defp validate_params(thunk, params) do
      if function_exported?(thunk, :validate_params, 1) do
        case thunk.validate_params(params) do
          {:ok, params} -> OK.success(params)
          {:error, reason} -> OK.failure(reason)
          _ -> OK.failure(Error.validation_error("Invalid return from thunk.validate_params/1"))
        end
      else
        OK.failure(
          Error.invalid_thunk("Module #{inspect(thunk)} is not a valid thunk: missing validate_params/1 function")
        )
      end
    end

    @spec do_run_with_retry(thunk(), params(), context(), run_opts()) :: {:ok, map()} | {:error, Error.t()}
    defp do_run_with_retry(thunk, params, context, opts) do
      max_retries = Keyword.get(opts, :max_retries, @default_max_retries)
      backoff = Keyword.get(opts, :backoff, @initial_backoff)
      do_run_with_retry(thunk, params, context, opts, 0, max_retries, backoff)
    end

    @spec do_run_with_retry(
            thunk(),
            params(),
            context(),
            run_opts(),
            non_neg_integer(),
            non_neg_integer(),
            non_neg_integer()
          ) :: {:ok, map()} | {:error, Error.t()}
    defp do_run_with_retry(thunk, params, context, opts, retry_count, max_retries, backoff) do
      case do_run(thunk, params, context, opts) do
        OK.success(result) ->
          OK.success(result)

        OK.failure(reason) ->
          if retry_count < max_retries do
            backoff = calculate_backoff(retry_count, backoff)
            :timer.sleep(backoff)
            do_run_with_retry(thunk, params, context, opts, retry_count + 1, max_retries, backoff)
          else
            OK.failure(reason)
          end
      end
    end

    @spec calculate_backoff(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
    defp calculate_backoff(retry_count, backoff) do
      (backoff * :math.pow(2, retry_count))
      |> round()
      |> min(30_000)
    end

    @spec do_run(thunk(), params(), context(), run_opts()) :: {:ok, map()} | {:error, Error.t()}
    defp do_run(thunk, params, context, opts) do
      timeout = Keyword.get(opts, :timeout)
      telemetry = Keyword.get(opts, :telemetry, :full)

      result =
        case telemetry do
          :silent ->
            execute_thunk_with_timeout(thunk, params, context, timeout)

          _ ->
            start_time = System.monotonic_time(:microsecond)
            start_span(thunk, params, context, telemetry)

            result = execute_thunk_with_timeout(thunk, params, context, timeout)

            end_time = System.monotonic_time(:microsecond)
            duration_us = end_time - start_time
            end_span(thunk, result, duration_us, telemetry)

            result
        end

      result
    end

    @spec start_span(thunk(), params(), context(), atom()) :: :ok
    defp start_span(thunk, params, context, telemetry) do
      metadata = %{
        thunk: thunk,
        params: params,
        context: context
      }

      emit_telemetry_event(:start, metadata, telemetry)
    end

    @spec end_span(thunk(), {:ok, map()} | {:error, Error.t()}, non_neg_integer(), atom()) :: :ok
    defp end_span(thunk, result, duration_us, telemetry) do
      metadata = get_metadata(thunk, result, duration_us, telemetry)
      status = if match?({:ok, _}, result), do: :complete, else: :error
      emit_telemetry_event(status, metadata, telemetry)
    end

    @spec get_metadata(thunk(), {:ok, map()} | {:error, Error.t()}, non_neg_integer(), atom()) :: map()
    defp get_metadata(thunk, result, duration_us, :full) do
      %{
        thunk: thunk,
        result: result,
        duration_us: duration_us,
        memory_usage: :erlang.memory(),
        process_info: get_process_info(),
        node: node()
      }
    end

    @spec get_metadata(thunk(), {:ok, map()} | {:error, Error.t()}, non_neg_integer(), atom()) :: map()
    defp get_metadata(thunk, result, duration_us, :minimal) do
      %{
        thunk: thunk,
        result: result,
        duration_us: duration_us
      }
    end

    @spec get_process_info() :: map()
    defp get_process_info do
      for key <- [:reductions, :message_queue_len, :total_heap_size, :garbage_collection],
          into: %{} do
        {key, self() |> Process.info(key) |> elem(1)}
      end
    end

    @spec emit_telemetry_event(atom(), map(), atom()) :: :ok
    defp emit_telemetry_event(event, metadata, telemetry) when telemetry in [:full, :minimal] do
      event_name = [:jido, :operation, event]
      measurements = %{system_time: System.system_time()}

      Logger.debug("Thunk #{metadata.thunk} #{event}", metadata)
      :telemetry.execute(event_name, measurements, metadata)
    end

    defp emit_telemetry_event(_, _, _), do: :ok

    @spec execute_thunk_with_timeout(thunk(), params(), context(), non_neg_integer()) ::
            {:ok, map()} | {:error, Error.t()}
    def execute_thunk_with_timeout(thunk, params, context, timeout)

    def execute_thunk_with_timeout(thunk, params, context, 0) do
      execute_thunk(thunk, params, context)
    end

    def execute_thunk_with_timeout(thunk, params, context, timeout) when is_integer(timeout) and timeout > 0 do
      parent = self()
      ref = make_ref()

      {pid, monitor_ref} =
        spawn_monitor(fn ->
          result =
            try do
              execute_thunk(thunk, params, context)
            catch
              kind, reason ->
                {:error, Error.execution_error("Caught #{kind}: #{inspect(reason)}")}
            end

          send(parent, {:done, ref, result})
        end)

      receive do
        {:done, ^ref, result} ->
          Process.demonitor(monitor_ref, [:flush])
          result

        {:DOWN, ^monitor_ref, :process, ^pid, :killed} ->
          {:error, Error.execution_error("Task was killed")}

        {:DOWN, ^monitor_ref, :process, ^pid, reason} ->
          {:error, Error.execution_error("Task exited: #{inspect(reason)}")}
      after
        timeout ->
          Process.exit(pid, :kill)

          receive do
            {:DOWN, ^monitor_ref, :process, ^pid, _} -> :ok
          after
            0 -> :ok
          end

          {:error, Error.timeout("Operation timed out after #{timeout}ms")}
      end
    end

    def execute_thunk_with_timeout(thunk, params, context, _timeout) do
      Logger.warning("Invalid timeout value, using default")
      execute_thunk_with_timeout(thunk, params, context, @default_timeout)
    end

    @spec execute_thunk(thunk(), params(), context()) :: {:ok, map()} | {:error, Error.t()}
    defp execute_thunk(thunk, params, context) do
      case thunk.run(params, context) do
        OK.success(result) ->
          OK.success(result)

        OK.failure(reason) ->
          OK.failure(Error.execution_error(reason))

        result ->
          OK.success(result)
      end
    rescue
      e in RuntimeError ->
        OK.failure(Error.execution_error("Runtime error: #{Exception.message(e)}"))

      e in ArgumentError ->
        OK.failure(Error.execution_error("Argument error: #{Exception.message(e)}"))

      e ->
        OK.failure(Error.execution_error("An unexpected error occurred during Thunk execution: #{inspect(e)}"))
    end
  end
end
