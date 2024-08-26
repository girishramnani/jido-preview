defmodule Jido.Operation.Thunk do
  @moduledoc """
  Defines a discrete, composable unit of functionality within the Jido system.

  Each Thunk represents a delayed computation that can be composed with others
  to build complex operations and workflows. Thunks are defined at compile-time
  and provide a consistent interface for validating inputs, executing operations,
  and handling results.

  ## Features

  - Compile-time configuration validation
  - Runtime input parameter validation
  - Consistent error handling and formatting
  - Extensible lifecycle hooks
  - JSON serialization support

  ## Usage

  To define a new Thunk, use the `Jido.Operation.Thunk` behavior in your module:

      defmodule MyThunk do
        use Jido.Operation.Thunk,
          name: "my_thunk",
          description: "Performs a specific operation",
          category: "processing",
          tags: ["example", "demo"],
          vsn: "1.0.0",
          schema: [
            input: [type: :string, required: true]
          ]

        @impl true
        def run(params, _context) do
          # Your thunk logic here
          {:ok, %{result: String.upcase(params.input)}}
        end
      end

  ## Callbacks

  Implementing modules must define the following callback:

  - `c:run/2`: Executes the main logic of the Thunk.

  Optional callbacks for custom behavior:

  - `c:on_before_validate_params/1`: Called before parameter validation.
  - `c:on_after_validate_params/1`: Called after parameter validation.
  - `c:on_after_run/1`: Called after the Thunk's main logic has executed.

  ## Error Handling

  Thunks use the `OK` monad for consistent error handling. Errors are wrapped
  in `Jido.Operation.Error` structs for uniform error reporting across the system.

  ## Parameter Validation

  > **Note on Validation:** The validation process for Thunks is intentionally loose.
  > Only fields specified in the schema are validated. Unspecified fields are not
  > validated, allowing for easier Thunk composition. This approach enables Thunks
  > to accept and pass along additional parameters that may be required by other
  > Thunks in a chain without causing validation errors.
  """

  alias Jido.Operation.Error

  require OK

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          category: String.t(),
          tags: [String.t()],
          vsn: String.t(),
          schema: NimbleOptions.schema()
        }

  @thunk_config_schema NimbleOptions.new!(
                         name: [
                           type: {:custom, __MODULE__, :validate_name, []},
                           required: true,
                           doc: "The name of the Thunk. Must contain only letters, numbers, and underscores."
                         ],
                         description: [
                           type: :string,
                           required: false,
                           doc: "A description of what the Thunk does."
                         ],
                         category: [
                           type: :string,
                           required: false,
                           doc: "The category of the Thunk."
                         ],
                         tags: [
                           type: {:list, :string},
                           default: [],
                           doc: "A list of tags associated with the Thunk."
                         ],
                         vsn: [
                           type: :string,
                           required: false,
                           doc: "The version of the Thunk."
                         ],
                         schema: [
                           type: :keyword_list,
                           default: [],
                           doc: "A NimbleOptions schema for validating the Thunk's input parameters."
                         ]
                       )

  defstruct [:name, :description, :category, :tags, :vsn, :schema]

  @doc """
  Defines a new Thunk module.

  This macro sets up the necessary structure and callbacks for a Thunk,
  including configuration validation and default implementations.

  ## Options

  See `@thunk_config_schema` for available options.

  ## Examples

      defmodule MyThunk do
        use Jido.Operation.Thunk,
          name: "my_thunk",
          description: "Performs a specific operation",
          schema: [
            input: [type: :string, required: true]
          ]

        @impl true
        def run(params, _context) do
          {:ok, %{result: String.upcase(params.input)}}
        end
      end

  """
  defmacro __using__(opts) do
    escaped_schema = Macro.escape(@thunk_config_schema)

    quote do
      @behaviour Jido.Operation.Thunk

      alias Jido.Operation.Thunk
      alias Jido.Operation.Thunk.Options

      require OK

      case NimbleOptions.validate(unquote(opts), unquote(escaped_schema)) do
        {:ok, validated_opts} ->
          @validated_opts validated_opts

          def name, do: @validated_opts[:name]
          def description, do: @validated_opts[:description]
          def category, do: @validated_opts[:category]
          def tags, do: @validated_opts[:tags]
          def vsn, do: @validated_opts[:vsn]
          def schema, do: @validated_opts[:schema]

          def to_json do
            %{
              name: @validated_opts[:name],
              description: @validated_opts[:description],
              category: @validated_opts[:category],
              tags: @validated_opts[:tags],
              vsn: @validated_opts[:vsn],
              schema: @validated_opts[:schema]
            }
          end

          @doc """
          Validates the input parameters for the Thunk.

          ## Examples

              iex> defmodule ExampleThunk do
              ...>   use Jido.Operation.Thunk,
              ...>     name: "example_thunk",
              ...>     schema: [
              ...>       input: [type: :string, required: true]
              ...>     ]
              ...> end
              ...> ExampleThunk.validate_params(%{input: "test"})
              {:ok, %{input: "test"}}

              iex> ExampleThunk.validate_params(%{})
              {:error, "Invalid parameters for Thunk: Required key :input not found"}

          """
          @spec validate_params(map()) :: {:ok, map()} | {:error, String.t()}
          def validate_params(params) do
            with {:ok, params} <- on_before_validate_params(params),
                 {:ok, validated_params} <- do_validate_params(params),
                 {:ok, after_params} <- on_after_validate_params(validated_params) do
              OK.success(after_params)
            else
              {:error, reason} -> OK.failure(reason)
            end
          end

          defp do_validate_params(params) do
            case @validated_opts[:schema] do
              [] ->
                OK.success(params)

              schema when is_list(schema) ->
                known_keys = Keyword.keys(schema)
                {known_params, unknown_params} = Map.split(params, known_keys)

                case NimbleOptions.validate(Enum.to_list(known_params), schema) do
                  {:ok, validated_params} ->
                    merged_params = Map.merge(unknown_params, Map.new(validated_params))
                    OK.success(merged_params)

                  {:error, %NimbleOptions.ValidationError{} = error} ->
                    error
                    |> Thunk.format_validation_error()
                    |> Error.validation_error()
                    |> OK.failure()
                end
            end
          end

          @doc """
          Executes the Thunk with the given parameters and context.

          The `run/2` function must be implemented in the module using Jido.Operation.Thunk.
          """
          @spec run(map(), map()) :: {:ok, map()} | {:error, any()}
          def run(params, context) do
            "run/2 must be implemented in in your Thunk"
            |> Error.config_error()
            |> OK.failure()
          end

          def on_before_validate_params(params), do: OK.success(params)
          def on_after_validate_params(params), do: OK.success(params)
          def on_after_run(result), do: OK.success(result)

          defoverridable on_before_validate_params: 1,
                         on_after_validate_params: 1,
                         run: 2,
                         on_after_run: 1

        {:error, error} ->
          error
          |> Thunk.format_config_error()
          |> Error.config_error()
          |> OK.failure()
      end
    end
  end

  @doc """
  Executes the Thunk with the given parameters and context.

  This callback must be implemented by modules using `Jido.Operation.Thunk`.

  ## Parameters

  - `params`: A map of validated input parameters.
  - `context`: A map containing any additional context for the operation.

  ## Returns

  - `{:ok, result}` where `result` is a map containing the operation's output.
  - `{:error, reason}` where `reason` describes why the operation failed.
  """
  @callback run(params :: map(), context :: map()) :: {:ok, map()} | {:error, any()}

  @doc """
  Called before parameter validation.

  This optional callback allows for pre-processing of input parameters
  before they are validated against the Thunk's schema.

  ## Parameters

  - `params`: A map of raw input parameters.

  ## Returns

  - `{:ok, modified_params}` where `modified_params` is a map of potentially modified parameters.
  - `{:error, reason}` if pre-processing fails.
  """
  @callback on_before_validate_params(params :: map()) :: {:ok, map()} | {:error, any()}

  @doc """
  Called after parameter validation.

  This optional callback allows for post-processing of validated parameters
  before they are passed to the `run/2` function.

  ## Parameters

  - `params`: A map of validated input parameters.

  ## Returns

  - `{:ok, modified_params}` where `modified_params` is a map of potentially modified parameters.
  - `{:error, reason}` if post-processing fails.
  """
  @callback on_after_validate_params(params :: map()) :: {:ok, map()} | {:error, any()}

  @doc """
  Called after the Thunk's main logic has executed.

  This optional callback allows for post-processing of the Thunk's result
  before it is returned to the caller.

  ## Parameters

  - `result`: The result map returned by the `run/2` function.

  ## Returns

  - `{:ok, modified_result}` where `modified_result` is a potentially modified result map.
  - `{:error, reason}` if post-processing fails.
  """
  @callback on_after_run(result :: map()) :: {:ok, map()} | {:error, any()}

  @doc """
  Raises an error indicating that Thunks cannot be defined at runtime.

  This function exists to prevent misuse of the Thunk system, as Thunks
  are designed to be defined at compile-time only.

  ## Returns

  Always returns `{:error, reason}` where `reason` is a config error.

  ## Examples

      iex> Jido.Operation.Thunk.new()
      {:error, %Jido.Operation.Error{type: :config_error, message: "Thunks should not be defined at runtime"}}

  """
  @spec new() :: {:error, Error.t()}
  @spec new(map() | keyword()) :: {:error, Error.t()}
  def new, do: new(%{})

  def new(_map_or_kwlist) do
    "Thunks should not be defined at runtime"
    |> Error.config_error()
    |> OK.failure()
  end

  @doc """
  Formats error messages for thunk configuration errors.

  ## Parameters

  - `error`: The error to format. Can be a `NimbleOptions.ValidationError` or any term.

  ## Returns

  A formatted error message as a string.

  ## Examples

      iex> error = %NimbleOptions.ValidationError{keys_path: [:name], message: "is invalid"}
      iex> Jido.Operation.Thunk.format_config_error(error)
      "Invalid configuration given to use Jido.Operation.Thunk for key [:name]: is invalid"

  """
  @spec format_config_error(NimbleOptions.ValidationError.t() | any()) :: String.t()
  def format_config_error(%NimbleOptions.ValidationError{keys_path: [], message: message}) do
    "Invalid configuration given to use Jido.Operation.Thunk: #{message}"
  end

  def format_config_error(%NimbleOptions.ValidationError{keys_path: keys_path, message: message}) do
    "Invalid configuration given to use Jido.Operation.Thunk for key #{inspect(keys_path)}: #{message}"
  end

  def format_config_error(error) when is_binary(error), do: error
  def format_config_error(error), do: inspect(error)

  @doc """
  Formats error messages for thunk validation errors.

  ## Parameters

  - `error`: The error to format. Can be a `NimbleOptions.ValidationError` or any term.

  ## Returns

  A formatted error message as a string.

  ## Examples

      iex> error = %NimbleOptions.ValidationError{keys_path: [:input], message: "is required"}
      iex> Jido.Operation.Thunk.format_validation_error(error)
      "Invalid parameters for Thunk at [:input]: is required"

  """
  @spec format_validation_error(NimbleOptions.ValidationError.t() | any()) :: String.t()
  def format_validation_error(%NimbleOptions.ValidationError{keys_path: [], message: message}) do
    "Invalid parameters for Thunk: #{message}"
  end

  def format_validation_error(%NimbleOptions.ValidationError{keys_path: keys_path, message: message}) do
    "Invalid parameters for Thunk at #{inspect(keys_path)}: #{message}"
  end

  def format_validation_error(error) when is_binary(error), do: error
  def format_validation_error(error), do: inspect(error)

  @doc """
  Validates the name of a Thunk.

  The name must contain only letters, numbers, and underscores.

  ## Parameters

  - `name`: The name to validate.

  ## Returns

  - `{:ok, name}` if the name is valid.
  - `{:error, reason}` if the name is invalid.

  ## Examples

      iex> Jido.Operation.Thunk.validate_name("valid_name_123")
      {:ok, "valid_name_123"}

      iex> Jido.Operation.Thunk.validate_name("invalid-name")
      {:error, %Jido.Operation.Error{type: :validation_error, message: "The name must contain only letters, numbers, and underscores."}}

  """
  @spec validate_name(any()) :: {:ok, String.t()} | {:error, Error.t()}
  def validate_name(name) when is_binary(name) do
    if Regex.match?(~r/^[a-zA-Z][a-zA-Z0-9_]*$/, name) do
      OK.success(name)
    else
      "The name must start with a letter and contain only letters, numbers, and underscores."
      |> Error.validation_error()
      |> OK.failure()
    end
  end

  def validate_name(_) do
    "Invalid name format."
    |> Error.validation_error()
    |> OK.failure()
  end
end
