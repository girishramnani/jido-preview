defmodule Jido.Operation.ErrorTest do
  use ExUnit.Case, async: true

  alias Jido.Operation.Error

  describe "error type functions" do
    test "create specific error types" do
      for type <- [
            :bad_request,
            :validation_error,
            :config_error,
            :execution_error,
            :operation_error,
            :internal_server_error,
            :timeout
          ] do
        error = apply(Error, type, ["Test message"])
        assert %Error{} = error
        assert error.type == type
        assert error.message == "Test message"
        assert error.details == nil
        assert is_list(error.stacktrace)
      end
    end

    test "create errors with details" do
      details = %{reason: "test"}

      for type <- [
            :bad_request,
            :validation_error,
            :config_error,
            :execution_error,
            :operation_error,
            :internal_server_error,
            :timeout
          ] do
        error = apply(Error, type, ["Test message", details])
        assert error.details == details
      end
    end

    test "create errors with custom stacktrace" do
      custom_stacktrace = [{__MODULE__, :some_function, 2, [file: "some_file.ex", line: 10]}]

      for type <- [
            :bad_request,
            :validation_error,
            :config_error,
            :execution_error,
            :operation_error,
            :internal_server_error,
            :timeout
          ] do
        error = apply(Error, type, ["Test message", nil, custom_stacktrace])
        assert error.stacktrace == custom_stacktrace
      end
    end
  end

  describe "to_map/1" do
    test "converts error struct to map" do
      error = Error.bad_request("Test message", %{field: "test"})
      map = Error.to_map(error)

      assert map == %{
               type: :bad_request,
               message: "Test message",
               details: %{field: "test"},
               stacktrace: error.stacktrace
             }
    end

    test "converts error struct to map without nil values" do
      error = Error.bad_request("Test message")
      map = Error.to_map(error)

      assert map == %{
               type: :bad_request,
               message: "Test message",
               stacktrace: error.stacktrace
             }

      refute Map.has_key?(map, :details)
    end
  end

  describe "capture_stacktrace/0" do
    test "returns a list" do
      assert is_list(Error.capture_stacktrace())
    end

    test "captures current stacktrace" do
      stacktrace = Error.capture_stacktrace()
      assert length(stacktrace) > 0
      assert {Jido.Operation.ErrorTest, _, _, _} = hd(stacktrace)
    end
  end
end
