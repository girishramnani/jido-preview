defmodule Jido.OperationExecuteTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Jido.Operation
  alias Jido.Operation.Error
  alias JidoTest.TestThunks.BasicThunk
  alias JidoTest.TestThunks.ContextThunk
  alias JidoTest.TestThunks.DelayThunk
  alias JidoTest.TestThunks.ErrorThunk
  alias JidoTest.TestThunks.KilledThunk
  alias JidoTest.TestThunks.NoParamsThunk
  alias JidoTest.TestThunks.NormalExitThunk
  alias JidoTest.TestThunks.RawResultThunk
  alias JidoTest.TestThunks.SlowKilledThunk
  alias JidoTest.TestThunks.SpawnerThunk

  describe "execute_thunk/3" do
    test "successfully executes a Thunk" do
      assert {:ok, %{value: 5}} = Operation.execute_thunk(BasicThunk, %{value: 5}, %{})
    end

    test "successfully executes a Thunk with context" do
      assert {:ok, %{result: "5 processed with context: %{context: \"test\"}"}} =
               Operation.execute_thunk(ContextThunk, %{input: 5}, %{context: "test"})
    end

    test "successfully executes a Thunk with no params" do
      assert {:ok, %{result: "No params"}} = Operation.execute_thunk(NoParamsThunk, %{}, %{})
    end

    test "successfully executes a Thunk with raw result" do
      assert {:ok, %{value: 5}} = Operation.execute_thunk(RawResultThunk, %{value: 5}, %{})
    end

    test "handles Thunk execution error" do
      assert {:error, %Error{type: :execution_error}} =
               Operation.execute_thunk(ErrorThunk, %{error_type: :validation}, %{})
    end

    test "handles runtime errors" do
      assert {:error, %Error{type: :execution_error, message: "Runtime error: Runtime error"}} =
               Operation.execute_thunk(ErrorThunk, %{error_type: :runtime}, %{})
    end

    test "handles argument errors" do
      assert {:error, %Error{type: :execution_error}} =
               Operation.execute_thunk(ErrorThunk, %{error_type: :argument}, %{})
    end

    test "handles unexpected errors" do
      assert {:error, %Error{type: :execution_error, message: "Runtime error: Custom error"}} =
               Operation.execute_thunk(ErrorThunk, %{error_type: :custom}, %{})
    end
  end

  describe "execute_thunk_with_timeout/4" do
    test "successfully executes a Thunk with no params" do
      assert {:ok, %{result: "No params"}} =
               Operation.execute_thunk_with_timeout(NoParamsThunk, %{}, %{}, 0)
    end

    test "executes quick thunk within timeout" do
      assert {:ok, %{value: 5}} ==
               Operation.execute_thunk_with_timeout(BasicThunk, %{value: 5}, %{}, 1000)
    end

    test "times out for slow thunk" do
      assert {:error, %Error{type: :timeout}} =
               Operation.execute_thunk_with_timeout(DelayThunk, %{delay: 1000}, %{}, 100)
    end

    test "handles very short timeout" do
      result = Operation.execute_thunk_with_timeout(DelayThunk, %{delay: 100}, %{}, 1)
      assert {:error, %Error{type: :timeout}} = result
    end

    test "handles thunk errors" do
      assert {:error, %Error{type: :execution_error}} =
               Operation.execute_thunk_with_timeout(
                 ErrorThunk,
                 %{error_type: :runtime},
                 %{},
                 1000
               )
    end

    test "handles unexpected errors during execution" do
      assert {:error, %Error{type: :execution_error, message: message}} =
               Operation.execute_thunk_with_timeout(ErrorThunk, %{type: :unexpected}, %{}, 1000)

      assert message =~ "Operation failed"
    end

    test "handles errors thrown during execution" do
      assert {:error, %Error{type: :execution_error, message: message}} =
               Operation.execute_thunk_with_timeout(ErrorThunk, %{type: :throw}, %{}, 1000)

      assert message =~ "Caught throw: \"Thunk threw an error\""
    end

    test "handles :DOWN message after killing the process" do
      test_pid = self()

      spawn(fn ->
        result = Operation.execute_thunk_with_timeout(SlowKilledThunk, %{}, %{}, 50)
        send(test_pid, {:result, result})
      end)

      assert_receive {:result, {:error, %Error{type: :timeout}}}, 1000
    end

    test "uses default timeout when not specified" do
      assert {:ok, %{result: "Async operation completed"}} ==
               Operation.execute_thunk_with_timeout(DelayThunk, %{delay: 80}, %{}, 0)
    end

    test "executes without timeout when timeout is zero" do
      assert {:ok, %{result: "Async operation completed"}} ==
               Operation.execute_thunk_with_timeout(DelayThunk, %{delay: 80}, %{}, 0)
    end

    test "logs warning and uses default timeout for invalid timeout value" do
      log =
        capture_log(fn ->
          assert {:ok, %{value: 5}} ==
                   Operation.execute_thunk_with_timeout(BasicThunk, %{value: 5}, %{}, -1)
        end)

      assert log =~ "Invalid timeout value, using default"
    end

    test "handles normal exit" do
      result = Operation.execute_thunk_with_timeout(NormalExitThunk, %{}, %{}, 1000)
      assert {:error, %Error{type: :execution_error, message: "Task exited: :normal"}} = result
    end

    test "handles killed tasks" do
      result = Operation.execute_thunk_with_timeout(KilledThunk, %{}, %{}, 1000)
      assert {:error, %Error{type: :execution_error, message: "Task was killed"}} = result
    end

    test "handles concurrent thunk execution" do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            Operation.execute_thunk_with_timeout(BasicThunk, %{value: i}, %{}, 1000)
          end)
        end

      results = Task.await_many(tasks)
      assert Enum.all?(results, fn {:ok, %{value: v}} -> is_integer(v) end)
    end

    test "handles thunk spawning multiple processes" do
      result = Operation.execute_thunk_with_timeout(SpawnerThunk, %{count: 10}, %{}, 1000)
      assert {:ok, %{result: "Multi-process operation completed"}} = result
      # Ensure no lingering processes
      :timer.sleep(150)
      process_list = Process.list()
      process_count = length(process_list)
      assert process_count <= :erlang.system_info(:process_count)
    end
  end
end
