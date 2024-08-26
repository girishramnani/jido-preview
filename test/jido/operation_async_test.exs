defmodule Jido.OperationAsyncTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Operation
  alias Jido.Operation.Error
  alias JidoTest.TestThunks.BasicThunk
  alias JidoTest.TestThunks.DelayThunk
  alias JidoTest.TestThunks.ErrorThunk

  describe "run_async/4" do
    test "returns an async_ref with pid and ref" do
      capture_log(fn ->
        result = Operation.run_async(BasicThunk, %{value: 5})
        assert is_map(result)
        assert is_pid(result.pid)
        assert is_reference(result.ref)
      end)
    end
  end

  describe "await/2" do
    test "returns the result of a successful async operation" do
      capture_log(fn ->
        async_ref = Operation.run_async(BasicThunk, %{value: 5}, %{}, timeout: 50)
        assert {:ok, %{value: 5}} = Operation.await(async_ref)
      end)
    end

    test "returns an error for a failed async operation" do
      capture_log(fn ->
        async_ref = Operation.run_async(ErrorThunk, %{error_type: :runtime}, %{}, timeout: 50)

        assert {:error, %Error{type: :execution_error, message: "Runtime error: Runtime error"}} =
                 Operation.await(async_ref)
      end)
    end

    test "returns a timeout error when the operation exceeds the timeout" do
      capture_log(fn ->
        async_ref = Operation.run_async(DelayThunk, %{delay: 200}, %{}, timeout: 75)

        assert {:error, %Error{type: :timeout, message: "Async operation timed out after 50ms"}} =
                 Operation.await(async_ref, 50)
      end)
    end
  end

  describe "cancel/1" do
    test "successfully cancels an async operation" do
      capture_log(fn ->
        async_ref = Operation.run_async(BasicThunk, %{value: 5})
        assert :ok = Operation.cancel(async_ref)

        refute Process.alive?(async_ref.pid)
      end)
    end

    test "returns ok when cancelling an already completed operation" do
      capture_log(fn ->
        async_ref = Operation.run_async(BasicThunk, %{value: 5})

        Operation.await(async_ref)
        assert :ok = Operation.cancel(async_ref)
      end)
    end

    test "accepts a pid directly" do
      capture_log(fn ->
        async_ref = Operation.run_async(BasicThunk, %{value: 5})
        assert :ok = Operation.cancel(async_ref.pid)
        refute Process.alive?(async_ref.pid)
      end)
    end

    test "returns an error for invalid input" do
      assert {:error, %Error{type: :invalid_async_ref}} = Operation.cancel("invalid")
    end
  end

  test "integration of run_async, await, and cancel" do
    capture_log(fn ->
      test_pid = self()
      async_ref = Operation.run_async(DelayThunk, %{delay: 2000}, %{}, timeout: 2000)

      spawn(fn ->
        result = Operation.await(async_ref, 100)
        send(test_pid, {:await_result, result})
      end)

      Process.sleep(50)
      Operation.cancel(async_ref)

      receive do
        {:await_result, result} ->
          assert {:error, %Error{type: :timeout} = error} = result
          assert error.message =~ "Async operation timed out after 100ms"
      after
        2000 ->
          flunk("Await did not complete in time")
      end

      refute Process.alive?(async_ref.pid)
    end)
  end
end
