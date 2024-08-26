defmodule Jido.Operation.ClosureTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Mock

  alias Jido.Operation
  alias Jido.Operation.Closure
  alias Jido.Operation.Error
  alias JidoTest.TestThunks.BasicThunk
  alias JidoTest.TestThunks.ContextThunk
  alias JidoTest.TestThunks.ErrorThunk

  describe "closure/3" do
    test "creates a closure that can be called with params" do
      capture_log(fn ->
        closure = Closure.closure(BasicThunk, %{})
        assert is_function(closure, 1)

        result = closure.(%{value: 5})
        assert {:ok, %{value: 5}} = result
      end)
    end

    test "closure preserves context and options" do
      with_mock Operation, run: fn _, _, _, _ -> {:ok, %{mocked: true}} end do
        closure = Closure.closure(ContextThunk, %{context_key: "value"}, timeout: 5000)
        closure.(%{input: "test"})

        assert_called(Operation.run(ContextThunk, %{input: "test"}, %{context_key: "value"}, timeout: 5000))
      end
    end

    test "closure handles errors from the thunk" do
      capture_log(fn ->
        closure = Closure.closure(ErrorThunk)

        assert {:error, %Error{type: :execution_error, message: "Runtime error: Runtime error"}} =
                 closure.(%{error_type: :runtime})
      end)
    end

    test "closure validates params before execution" do
      capture_log(fn ->
        closure = Closure.closure(BasicThunk, %{})
        assert {:error, %Error{type: :validation_error}} = closure.(%{invalid: "params"})
      end)
    end
  end

  describe "async_closure/3" do
    test "creates an async closure that returns an async_ref" do
      capture_log(fn ->
        async_closure = Closure.async_closure(BasicThunk)
        assert is_function(async_closure, 1)

        async_ref = async_closure.(%{value: 10})
        assert is_map(async_ref)
        assert is_pid(async_ref.pid)
        assert is_reference(async_ref.ref)

        assert {:ok, %{value: 10}} = Operation.await(async_ref)
      end)
    end

    test "async_closure preserves context and options" do
      capture_log(fn ->
        with_mock Operation, run_async: fn _, _, _, _ -> %{ref: make_ref(), pid: self()} end do
          async_closure = Closure.async_closure(ContextThunk, %{async_context: true}, timeout: 10_000)
          async_closure.(%{input: "async_test"})

          assert_called(
            Operation.run_async(ContextThunk, %{input: "async_test"}, %{async_context: true}, timeout: 10_000)
          )
        end
      end)
    end

    test "async_closure handles errors from the thunk" do
      capture_log(fn ->
        async_closure = Closure.async_closure(ErrorThunk)
        async_ref = async_closure.(%{error_type: :runtime})

        assert {:error, %Error{type: :execution_error, message: "Runtime error: Runtime error"}} =
                 Operation.await(async_ref)
      end)
    end
  end

  describe "error handling and edge cases" do
    test "closure handles invalid thunk" do
      assert_raise FunctionClauseError, fn ->
        Closure.closure("not_a_module")
      end
    end

    test "async_closure handles invalid thunk" do
      assert_raise FunctionClauseError, fn ->
        Closure.async_closure("not_a_module")
      end
    end

    test "closure with empty context and opts" do
      closure = Closure.closure(BasicThunk)
      assert {:error, %Error{type: :validation_error}} = closure.(%{})
    end

    test "async_closure with empty context and opts" do
      async_closure = Closure.async_closure(BasicThunk)
      async_ref = async_closure.(%{})
      assert {:error, %Error{type: :validation_error}} = Operation.await(async_ref)
    end
  end
end
