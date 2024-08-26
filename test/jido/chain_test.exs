defmodule Jido.Operation.ChainTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias Jido.Operation.Chain
  alias Jido.Operation.Error
  alias JidoTest.TestThunks.Add
  alias JidoTest.TestThunks.ContextAwareMultiply
  alias JidoTest.TestThunks.ErrorThunk
  alias JidoTest.TestThunks.Multiply
  alias JidoTest.TestThunks.Square
  alias JidoTest.TestThunks.Subtract
  alias JidoTest.TestThunks.WriteFile

  describe "chain/3" do
    test "executes a simple chain of operations successfully" do
      capture_log(fn ->
        result = Chain.chain([Add, Multiply], %{value: 5, amount: 2})
        assert {:ok, %{value: 14, amount: 2}} = result
      end)
    end

    test "supports new syntax with operation options" do
      capture_log(fn ->
        result =
          Chain.chain(
            [
              Add,
              {WriteFile, [file_name: "test.txt", content: "Hello"]},
              Multiply
            ],
            %{value: 1, amount: 2}
          )

        assert {:ok, %{value: 6, written_file: "test.txt"}} = result
      end)
    end

    test "executes a chain with mixed operation formats" do
      capture_log(fn ->
        result = Chain.chain([Add, {Multiply, [amount: 3]}, Subtract], %{value: 5})
        assert {:ok, %{value: 15, amount: 3}} = result
      end)
    end

    test "handles errors in the chain" do
      capture_log(fn ->
        result = Chain.chain([Add, ErrorThunk, Multiply], %{value: 5, error_type: :runtime})
        assert {:error, %Error{type: :execution_error, message: "Runtime error: Runtime error"}} = result
      end)
    end

    test "stops execution on first error" do
      capture_log(fn ->
        result = Chain.chain([Add, ErrorThunk, Multiply], %{value: 5, error_type: :runtime})
        assert {:error, %Error{}} = result
        refute match?({:ok, %{value: _}}, result)
      end)
    end

    test "handles invalid operations in the chain" do
      capture_log(fn ->
        result = Chain.chain([Add, :invalid_operation, Multiply], %{value: 5})

        assert {:error, %Error{type: :invalid_thunk, message: "Failed to compile module :invalid_operation: :nofile"}} =
                 result
      end)
    end

    test "executes chain asynchronously" do
      capture_log(fn ->
        task = Chain.chain([Add, Multiply], %{value: 5}, async: true)
        assert %Task{} = task
        assert {:ok, %{value: 12}} = Task.await(task)
      end)
    end

    test "passes context to operations" do
      capture_log(fn ->
        context = %{multiplier: 3}
        result = Chain.chain([Add, ContextAwareMultiply], %{value: 5}, context: context)
        assert {:ok, %{value: 18}} = result
      end)
    end

    test "logs debug messages for each operation" do
      log =
        capture_log(fn ->
          Chain.chain([Add, Multiply], %{value: 5})
        end)

      assert log =~ "Executing operation in chain"
      assert log =~ "Thunk Elixir.JidoTest.TestThunks.Add complete"
      assert log =~ "Thunk Elixir.JidoTest.TestThunks.Multiply complete"
    end

    test "logs warnings for failed operations" do
      log =
        capture_log(fn ->
          Chain.chain([Add, ErrorThunk], %{value: 5, error_type: :runtime})
        end)

      assert log =~ "Operation in chain failed"
      assert log =~ "Thunk Elixir.JidoTest.TestThunks.ErrorThunk error"
    end

    test "executes a complex chain of operations" do
      capture_log(fn ->
        result =
          Chain.chain(
            [
              Add,
              {Multiply, [amount: 3]},
              Subtract,
              {Square, [amount: 2]}
            ],
            %{value: 10}
          )

        assert {:ok, %{value: 900}} = result
      end)
    end
  end
end
