defmodule Jido.OperationRunTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias Jido.Operation
  alias Jido.Operation.Error
  alias JidoTest.TestThunks.BasicThunk
  alias JidoTest.TestThunks.DelayThunk
  alias JidoTest.TestThunks.ErrorThunk
  alias JidoTest.TestThunks.RetryThunk

  @attempts_table :operation_run_test_attempts

  setup do
    :ets.new(@attempts_table, [:set, :public, :named_table])
    :ets.insert(@attempts_table, {:attempts, 0})

    on_exit(fn ->
      unless :ets.info(@attempts_table) == :undefined do
        :ets.delete(@attempts_table)
      end
    end)

    {:ok, attempts_table: @attempts_table}
  end

  describe "run/4" do
    test "executes thunk successfully" do
      with_mocks([
        {System, [], [monotonic_time: fn :microsecond -> 0 end]},
        {:telemetry, [], [execute: fn _, _, _ -> :ok end]}
      ]) do
        log =
          capture_log(fn ->
            assert {:ok, %{value: 5}} = Operation.run(BasicThunk, %{value: 5})
          end)

        assert log =~ "Thunk Elixir.JidoTest.TestThunks.BasicThunk start"
        assert log =~ "Thunk Elixir.JidoTest.TestThunks.BasicThunk complete"
        assert called(:telemetry.execute([:jido, :operation, :start], :_, :_))
        assert called(:telemetry.execute([:jido, :operation, :complete], :_, :_))
      end
    end

    test "handles thunk error" do
      with_mocks([
        {System, [], [monotonic_time: fn :microsecond -> 0 end]},
        {:telemetry, [], [execute: fn _, _, _ -> :ok end]}
      ]) do
        log =
          capture_log(fn ->
            assert {:error, %Error{}} = Operation.run(ErrorThunk, %{}, %{}, timeout: 50)
          end)

        assert log =~ "Thunk Elixir.JidoTest.TestThunks.ErrorThunk start"
        assert log =~ "Thunk Elixir.JidoTest.TestThunks.ErrorThunk error"
        assert called(:telemetry.execute([:jido, :operation, :start], :_, :_))
        assert called(:telemetry.execute([:jido, :operation, :error], :_, :_))
      end
    end

    test "retries on error and then succeeds", %{attempts_table: attempts_table} do
      with_mocks([
        {System, [], [monotonic_time: fn :microsecond -> 0 end]},
        {:telemetry, [], [execute: fn _, _, _ -> :ok end]}
      ]) do
        capture_log(fn ->
          result =
            Operation.run(
              RetryThunk,
              %{max_attempts: 3, failure_type: :error},
              %{attempts_table: attempts_table},
              max_retries: 2,
              backoff: 10
            )

          assert {:ok, %{result: "success after 3 attempts"}} = result
          assert :ets.lookup(attempts_table, :attempts) == [{:attempts, 3}]
        end)
      end
    end

    test "fails after max retries", %{attempts_table: attempts_table} do
      with_mocks([
        {System, [], [monotonic_time: fn :microsecond -> 0 end]},
        {:telemetry, [], [execute: fn _, _, _ -> :ok end]}
      ]) do
        capture_log(fn ->
          result =
            Operation.run(
              RetryThunk,
              %{max_attempts: 5, failure_type: :error},
              %{attempts_table: attempts_table},
              max_retries: 2,
              backoff: 10
            )

          assert {:error, %Error{}} = result
          assert :ets.lookup(attempts_table, :attempts) == [{:attempts, 3}]
        end)
      end
    end

    test "handles invalid params" do
      assert {:error, %Error{}} = Operation.run(BasicThunk, %{invalid: "params"})
    end

    test "handles timeout" do
      capture_log(fn ->
        assert {:error, %Error{message: "Operation timed out after 50ms"}} =
                 Operation.run(DelayThunk, %{delay: 1000}, %{}, timeout: 50)
      end)
    end
  end

  describe "normalize_params/1" do
    test "normalizes a map" do
      params = %{key: "value"}
      assert {:ok, ^params} = Operation.normalize_params(params)
    end

    test "normalizes a keyword list" do
      params = [key: "value"]
      assert {:ok, %{key: "value"}} = Operation.normalize_params(params)
    end

    test "normalizes {:ok, map}" do
      params = {:ok, %{key: "value"}}
      assert {:ok, %{key: "value"}} = Operation.normalize_params(params)
    end

    test "normalizes {:ok, keyword list}" do
      params = {:ok, [key: "value"]}
      assert {:ok, %{key: "value"}} = Operation.normalize_params(params)
    end

    test "handles {:error, reason}" do
      params = {:error, "some error"}

      assert {:error, %Error{type: :validation_error, message: "some error"}} =
               Operation.normalize_params(params)
    end

    test "passes through %Error{} with different types" do
      errors = [
        %Error{type: :validation_error, message: "validation failed"},
        %Error{type: :execution_error, message: "execution failed"},
        %Error{type: :timeout_error, message: "operation timed out"}
      ]

      for error <- errors do
        assert {:error, ^error} = Operation.normalize_params(error)
      end
    end

    test "returns error for invalid params" do
      params = "invalid"

      assert {:error, %Error{type: :validation_error, message: "Invalid params type: " <> _}} =
               Operation.normalize_params(params)
    end
  end

  describe "normalize_context/1" do
    test "normalizes a map" do
      context = %{key: "value"}
      assert {:ok, ^context} = Operation.normalize_context(context)
    end

    test "normalizes a keyword list" do
      context = [key: "value"]
      assert {:ok, %{key: "value"}} = Operation.normalize_context(context)
    end

    test "returns error for invalid context" do
      context = "invalid"

      assert {:error, %Error{type: :validation_error, message: "Invalid context type: " <> _}} =
               Operation.normalize_context(context)
    end
  end

  describe "validate_thunk/1" do
    defmodule NotAThunk do
      @moduledoc false
      def validate_params(_), do: :ok
    end

    test "returns :ok for valid thunk" do
      assert :ok = Operation.validate_thunk(BasicThunk)
    end

    test "returns error for thunk without run/2" do
      assert {:error,
              %Error{
                type: :invalid_thunk,
                message: "Module Jido.OperationRunTest.NotAThunk is not a valid thunk: missing run/2 function"
              }} = Operation.validate_thunk(NotAThunk)
    end
  end

  describe "validate_params/2" do
    test "returns validated params for valid params" do
      assert {:ok, %{value: 5}} = Operation.validate_params(BasicThunk, %{value: 5})
    end

    test "returns error for invalid params" do
      {:error, %Error{type: :validation_error, message: error_message}} =
        Operation.validate_params(BasicThunk, %{invalid: "params"})

      assert error_message =~ "Invalid parameters for Thunk"
    end
  end
end
