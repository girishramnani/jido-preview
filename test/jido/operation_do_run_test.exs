defmodule Jido.OperationDoRunTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias Jido.Operation
  alias JidoTest.TestThunks.BasicThunk
  alias JidoTest.TestThunks.ErrorThunk
  alias JidoTest.TestThunks.RetryThunk

  @attempts_table :operation_do_run_test_attempts

  describe "do_run/3" do
    test "executes thunk with full telemetry" do
      with_mocks([
        {System, [], [monotonic_time: fn :microsecond -> 0 end]},
        {:telemetry, [], [execute: fn _, _, _ -> :ok end]}
      ]) do
        log =
          capture_log(fn ->
            assert {:ok, %{value: 5}} =
                     Operation.do_run(BasicThunk, %{value: 5}, %{}, telemetry: :full)
          end)

        assert log =~ "Thunk Elixir.JidoTest.TestThunks.BasicThunk start"
        assert log =~ "Thunk Elixir.JidoTest.TestThunks.BasicThunk complete"
        assert called(:telemetry.execute([:jido, :operation, :start], :_, :_))
        assert called(:telemetry.execute([:jido, :operation, :complete], :_, :_))
      end
    end

    test "executes thunk with minimal telemetry" do
      with_mocks([
        {System, [], [monotonic_time: fn :microsecond -> 0 end]},
        {:telemetry, [], [execute: fn _, _, _ -> :ok end]}
      ]) do
        log =
          capture_log(fn ->
            assert {:ok, %{value: 5}} =
                     Operation.do_run(BasicThunk, %{value: 5}, %{}, telemetry: :minimal)
          end)

        assert log =~ "Thunk Elixir.JidoTest.TestThunks.BasicThunk start"
        assert log =~ "Thunk Elixir.JidoTest.TestThunks.BasicThunk complete"
        assert called(:telemetry.execute([:jido, :operation, :start], :_, :_))
        assert called(:telemetry.execute([:jido, :operation, :complete], :_, :_))
      end
    end

    test "executes thunk in silent mode" do
      with_mock(System, monotonic_time: fn :microsecond -> 0 end) do
        log =
          capture_log(fn ->
            assert {:ok, %{value: 5}} =
                     Operation.do_run(BasicThunk, %{value: 5}, %{},
                       telemetry: :silent,
                       timeout: 0
                     )
          end)

        assert log == ""
        assert not called(System.monotonic_time(:microsecond))
      end
    end

    test "handles thunk error" do
      with_mocks([
        {System, [], [monotonic_time: fn :microsecond -> 0 end]},
        {:telemetry, [], [execute: fn _, _, _ -> :ok end]}
      ]) do
        log =
          capture_log(fn ->
            assert {:error, _} = Operation.do_run(ErrorThunk, %{}, %{}, telemetry: :full)
          end)

        assert log =~ "Thunk Elixir.JidoTest.TestThunks.ErrorThunk start"
        assert log =~ "Thunk Elixir.JidoTest.TestThunks.ErrorThunk error"
        assert called(:telemetry.execute([:jido, :operation, :start], :_, :_))
        assert called(:telemetry.execute([:jido, :operation, :error], :_, :_))
      end
    end
  end

  describe "get_metadata/4" do
    test "returns full metadata" do
      result = {:ok, %{result: 10}}
      metadata = Operation.get_metadata(BasicThunk, result, 1000, :full)

      assert metadata.thunk == BasicThunk
      assert metadata.result == result
      assert metadata.duration_us == 1000
      assert is_list(metadata.memory_usage)
      assert Keyword.keyword?(metadata.memory_usage)
      assert is_map(metadata.process_info)
      assert is_atom(metadata.node)
    end

    test "returns minimal metadata" do
      result = {:ok, %{result: 10}}
      metadata = Operation.get_metadata(BasicThunk, result, 1000, :minimal)

      assert metadata == %{
               thunk: BasicThunk,
               result: result,
               duration_us: 1000
             }
    end
  end

  describe "get_process_info/0" do
    test "returns process info" do
      info = Operation.get_process_info()

      assert is_map(info)
      assert Map.has_key?(info, :reductions)
      assert Map.has_key?(info, :message_queue_len)
      assert Map.has_key?(info, :total_heap_size)
      assert Map.has_key?(info, :garbage_collection)
    end
  end

  describe "emit_telemetry_event/3" do
    test "emits telemetry event for full mode" do
      with_mock(:telemetry, execute: fn _, _, _ -> :ok end) do
        log =
          capture_log(fn ->
            Operation.emit_telemetry_event(
              :test_event,
              %{thunk: BasicThunk, test: "data"},
              :full
            )
          end)

        assert log =~ "Thunk Elixir.JidoTest.TestThunks.BasicThunk test_event"
        assert called(:telemetry.execute([:jido, :operation, :test_event], :_, :_))
      end
    end

    test "emits telemetry event for minimal mode" do
      with_mock(:telemetry, execute: fn _, _, _ -> :ok end) do
        log =
          capture_log(fn ->
            Operation.emit_telemetry_event(
              :test_event,
              %{thunk: BasicThunk, test: "data"},
              :minimal
            )
          end)

        assert log =~ "Thunk Elixir.JidoTest.TestThunks.BasicThunk test_event"
        assert called(:telemetry.execute([:jido, :operation, :test_event], :_, :_))
      end
    end

    test "does not emit telemetry event for silent mode" do
      with_mock(:telemetry, execute: fn _, _, _ -> :ok end) do
        log =
          capture_log(fn ->
            Operation.emit_telemetry_event(
              :test_event,
              %{thunk: BasicThunk, test: "data"},
              :silent
            )
          end)

        assert log == ""
        assert not called(:telemetry.execute(:_, :_, :_))
      end
    end
  end

  describe "do_run_with_retry/4" do
    setup do
      # Create the ETS table with a static name
      :ets.new(@attempts_table, [:set, :public, :named_table])
      :ets.insert(@attempts_table, {:attempts, 0})

      on_exit(fn ->
        # Delete the table in the on_exit callback
        unless :ets.info(@attempts_table) == :undefined do
          :ets.delete(@attempts_table)
        end
      end)

      {:ok, attempts_table: @attempts_table}
    end

    test "succeeds on first try" do
      with_mocks([
        {System, [], [monotonic_time: fn :microsecond -> 0 end]},
        {:telemetry, [], [execute: fn _, _, _ -> :ok end]}
      ]) do
        capture_log(fn ->
          assert {:ok, %{value: 5}} =
                   Operation.do_run_with_retry(BasicThunk, %{value: 5}, %{}, [])
        end)
      end
    end

    test "retries on error and then succeeds", %{attempts_table: attempts_table} do
      with_mocks([
        {System, [], [monotonic_time: fn :microsecond -> 0 end]},
        {:telemetry, [], [execute: fn _, _, _ -> :ok end]}
      ]) do
        capture_log(fn ->
          result =
            Operation.do_run_with_retry(
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

    test "retries on exception and then succeeds", %{attempts_table: attempts_table} do
      with_mocks([
        {System, [], [monotonic_time: fn :microsecond -> 0 end]},
        {:telemetry, [], [execute: fn _, _, _ -> :ok end]}
      ]) do
        capture_log(fn ->
          result =
            Operation.do_run_with_retry(
              RetryThunk,
              %{max_attempts: 3, failure_type: :exception},
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
            Operation.do_run_with_retry(
              RetryThunk,
              %{max_attempts: 5, failure_type: :error},
              %{attempts_table: attempts_table},
              max_retries: 2,
              backoff: 10
            )

          assert {:error, _} = result
          assert :ets.lookup(attempts_table, :attempts) == [{:attempts, 3}]
        end)
      end
    end
  end
end
