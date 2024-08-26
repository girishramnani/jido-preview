defmodule JidoTest.Operation.ThunkTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Jido.Operation.Error
  alias Jido.Operation.Thunk
  alias JidoTest.TestThunks.Add
  alias JidoTest.TestThunks.ConcurrentThunk
  alias JidoTest.TestThunks.Divide
  alias JidoTest.TestThunks.ErrorThunk
  alias JidoTest.TestThunks.FullThunk
  alias JidoTest.TestThunks.LongRunningThunk
  alias JidoTest.TestThunks.Multiply
  alias JidoTest.TestThunks.NoSchema
  alias JidoTest.TestThunks.RateLimitedThunk
  alias JidoTest.TestThunks.StreamingThunk
  alias JidoTest.TestThunks.Subtract

  require OK

  describe "thunk naming" do
    test "thunk name is the module name" do
      assert FullThunk.name() == "full_thunk"
    end

    test "validate_name accepts valid names" do
      assert {:ok, "valid_name"} = Thunk.validate_name("valid_name")
      assert {:ok, "valid_name_123"} = Thunk.validate_name("valid_name_123")
      assert {:ok, "VALID_NAME"} = Thunk.validate_name("VALID_NAME")
    end

    test "validate_name rejects invalid names" do
      assert {:error, %Error{type: :validation_error}} = Thunk.validate_name("invalid-name")
      assert {:error, %Error{type: :validation_error}} = Thunk.validate_name("invalid name")
      assert {:error, %Error{type: :validation_error}} = Thunk.validate_name("123invalid")
      assert {:error, %Error{type: :validation_error}} = Thunk.validate_name("")
    end

    test "validate_name rejects non-string inputs" do
      assert {:error, %Error{type: :validation_error}} = Thunk.validate_name(123)
      assert {:error, %Error{type: :validation_error}} = Thunk.validate_name(%{})
      assert {:error, %Error{type: :validation_error}} = Thunk.validate_name(nil)
    end
  end

  describe "error formatting" do
    test "format_config_error formats NimbleOptions.ValidationError" do
      error = %NimbleOptions.ValidationError{keys_path: [:name], message: "is invalid"}
      formatted = Thunk.format_config_error(error)

      assert formatted ==
               "Invalid configuration given to use Jido.Operation.Thunk for key [:name]: is invalid"
    end

    test "format_config_error formats NimbleOptions.ValidationError with empty keys_path" do
      error = %NimbleOptions.ValidationError{keys_path: [], message: "is invalid"}
      formatted = Thunk.format_config_error(error)
      assert formatted == "Invalid configuration given to use Jido.Operation.Thunk: is invalid"
    end

    test "format_config_error handles binary errors" do
      assert Thunk.format_config_error("Some error") == "Some error"
    end

    test "format_config_error handles other error types" do
      assert Thunk.format_config_error(:some_atom) == ":some_atom"
    end

    test "format_validation_error formats NimbleOptions.ValidationError" do
      error = %NimbleOptions.ValidationError{keys_path: [:input], message: "is required"}
      formatted = Thunk.format_validation_error(error)
      assert formatted == "Invalid parameters for Thunk at [:input]: is required"
    end

    test "format_validation_error formats NimbleOptions.ValidationError with empty keys_path" do
      error = %NimbleOptions.ValidationError{keys_path: [], message: "is invalid"}
      formatted = Thunk.format_validation_error(error)
      assert formatted == "Invalid parameters for Thunk: is invalid"
    end

    test "format_validation_error handles binary errors" do
      assert Thunk.format_validation_error("Some error") == "Some error"
    end

    test "format_validation_error handles other error types" do
      assert Thunk.format_validation_error(:some_atom) == ":some_atom"
    end
  end

  describe "thunk creation and metadata" do
    test "creates a valid thunk with all options" do
      assert FullThunk.name() == "full_thunk"
      assert FullThunk.description() == "A full thunk for testing"
      assert FullThunk.category() == "test"
      assert FullThunk.tags() == ["test", "full"]
      assert FullThunk.vsn() == "1.0.0"

      assert FullThunk.schema() == [
               a: [type: :integer, required: true],
               b: [type: :integer, required: true]
             ]
    end

    test "creates a valid thunk with no schema" do
      assert NoSchema.name() == "add_two"
      assert NoSchema.description() == "Adds 2 to the input value"
      assert NoSchema.schema() == []
    end

    test "to_json returns correct representation" do
      json = FullThunk.to_json()
      assert json.name == "full_thunk"
      assert json.description == "A full thunk for testing"
      assert json.category == "test"
      assert json.tags == ["test", "full"]
      assert json.vsn == "1.0.0"

      assert json.schema == [
               a: [type: :integer, required: true],
               b: [type: :integer, required: true]
             ]
    end

    test "schema validation covers all types" do
      valid_params = %{a: 42, b: 2}

      assert {:ok, validated} = FullThunk.validate_params(valid_params)
      assert validated.a == 42
      assert validated.b == 2

      invalid_params = %{a: "not an integer", b: 2}

      assert {:error, %Error{type: :validation_error, message: error_message}} =
               FullThunk.validate_params(invalid_params)

      assert error_message =~ "Parameter 'a' must be a positive integer"
    end
  end

  describe "thunk execution" do
    test "executes a valid thunk successfully" do
      assert {:ok, result} = FullThunk.run(%{a: 5, b: 2}, %{})
      assert result.a == 5
      assert result.b == 2
      assert result.result == 7
    end

    test "executes basic arithmetic thunks" do
      assert {:ok, %{value: 6}} = Add.run(%{value: 5, amount: 1}, %{})
      assert {:ok, %{value: 10}} = Multiply.run(%{value: 5, amount: 2}, %{})
      assert {:ok, %{value: 3}} = Subtract.run(%{value: 5, amount: 2}, %{})
      assert {:ok, %{value: 2.5}} = Divide.run(%{value: 5, amount: 2}, %{})
    end

    test "handles division by zero" do
      assert_raise RuntimeError, "Cannot divide by zero", fn ->
        Divide.run(%{value: 5, amount: 0}, %{})
      end
    end

    test "handles different error scenarios" do
      assert {:error, "Validation error"} =
               ErrorThunk.run(%{error_type: :validation}, %{})

      assert_raise RuntimeError, "Runtime error", fn ->
        ErrorThunk.run(%{error_type: :runtime}, %{})
      end
    end
  end

  describe "parameter validation" do
    test "validates required parameters" do
      assert {:error, %Error{type: :validation_error, message: error_message}} =
               FullThunk.validate_params(%{})

      assert error_message =~ "Parameter 'a' must be a positive integer"
    end

    test "validates parameter types" do
      assert {:error, %Error{type: :validation_error, message: error_message}} =
               FullThunk.validate_params(%{a: "not an integer", b: 2})

      assert error_message =~ "Parameter 'a' must be a positive integer"
    end
  end

  describe "error handling" do
    test "new returns an error tuple" do
      assert {:error, %Error{type: :config_error, message: error_message}} = Thunk.new()
      assert error_message =~ "Thunks should not be defined at runtime"
    end
  end

  describe "property-based tests" do
    property "valid thunk always returns a result for valid input" do
      check all(
              a <- integer(),
              b <- integer(1..1000)
            ) do
        params = %{a: a, b: b}
        assert {:ok, result} = FullThunk.run(params, %{})
        assert result.a == a
        assert result.b == b
        assert result.result == a + b
      end
    end
  end

  describe "edge cases" do
    test "handles very large numbers in arithmetic operations" do
      large_number = 1_000_000_000_000_000_000_000
      assert {:ok, result} = Add.run(%{value: large_number, amount: 1}, %{})
      assert result.value == large_number + 1
    end
  end

  describe "advanced thunks" do
    test "long running thunk" do
      assert {:ok, "Operation completed"} = LongRunningThunk.run(%{}, %{})
    end

    test "rate limited thunk" do
      Enum.each(1..5, fn _ ->
        assert {:ok, _} = RateLimitedThunk.run(%{operation: "test"}, %{})
      end)

      assert {:error, "Rate limit exceeded. Please try again later."} =
               RateLimitedThunk.run(%{operation: "test"}, %{})
    end

    test "streaming thunk" do
      assert {:ok, %{stream: stream}} = StreamingThunk.run(%{chunk_size: 2, total_items: 10}, %{})
      assert Enum.to_list(stream) == [3, 7, 11, 15, 19]
    end

    test "concurrent thunk" do
      assert {:ok, %{results: results}} = ConcurrentThunk.run(%{inputs: [1, 2, 3, 4, 5]}, %{})
      assert length(results) == 5
      assert Enum.all?(results, fn r -> r in [2, 4, 6, 8, 10] end)
    end
  end
end
