# Jido

[![Build Status](https://github.com/your-org/jido/workflows/CI/badge.svg)](https://github.com/your-org/jido/actions) [![Hex.pm](https://img.shields.io/hexpm/v/jido.svg)](https://hex.pm/packages/jido) [![Documentation](https://img.shields.io/badge/documentation-gray)](https://hexdocs.pm/jido)

Jido is a robust, composable operation framework for building scalable and fault-tolerant distributed systems in Elixir. It provides a simple yet powerful abstraction called "Thunks" for defining and executing discrete units of work across distributed environments.

## Features

- **Composable Operations**: Build complex workflows by chaining simple Thunks
- **Distributed Execution**: Run Thunks across multiple nodes for enhanced scalability
- **Fault Tolerance**: Built-in error handling and retry mechanisms
- **Asynchronous Processing**: Execute Thunks asynchronously for improved performance
- **Flexible Schemas**: Define input/output schemas for your Thunks
- **Context Awareness**: Pass contextual information to your Thunks
- **Comprehensive Testing**: Includes utilities for unit and integration testing

## Installation

Add `jido` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido, "~> 0.1.0"}
  ]
end
```

## Defining Your First Thunk

Here's an example of defining a Thunk that calculates the area of a rectangle:

```elixir
defmodule MyApp.Thunks.CalculateArea do
  use Jido.Operation.Thunk,
    name: "calculate_area",
    description: "Calculates the area of a rectangle",
    schema: [
      width: [type: :float, required: true],
      height: [type: :float, required: true]
    ]

  @impl true
  def run(params, context) do
    area = params.width * params.height
    {:ok, %{area: area, unit: context[:unit] || "square units"}}
  end
end
```

This Thunk:
- Has a name and description
- Defines a schema for its input parameters
- Implements the `run/2` callback to perform the calculation
- Uses the context to provide additional information (unit of measurement)

## Running Your Thunk

To execute a Thunk, use the `Jido.Operation.run/4` function:

```elixir
alias MyApp.Thunks.CalculateArea

{:ok, result} = Jido.Operation.run(CalculateArea, %{width: 5, height: 3}, %{unit: "meters"})
# => {:ok, %{area: 15, unit: "meters"}}
```

## Async Thunks

For long-running operations, you can run Thunks asynchronously:

```elixir
async_ref = Jido.Operation.run_async(CalculateArea, %{width: 10, height: 20})
# Do other work...
{:ok, result} = Jido.Operation.await(async_ref)
```

## Closures

Jido supports closures for creating dynamic Thunks. Use list syntax for single-step closures and tuple syntax for multi-step closures:

```elixir
# Single-step closure
double_area = [CalculateArea, fn result -> {:ok, %{area: result.area * 2}} end]
Jido.Operation.run(double_area, %{width: 5, height: 3})
# => {:ok, %{area: 30}}

# Multi-step closure
complex_calculation = {CalculateArea, fn result ->
  perimeter = (result.width + result.height) * 2
  {:ok, %{area: result.area, perimeter: perimeter}}
end}
Jido.Operation.run(complex_calculation, %{width: 5, height: 3})
# => {:ok, %{area: 15, perimeter: 16}}
```

## Chaining

Thunks can be easily chained to create complex workflows:

```elixir
workflow = [
  CalculateArea,
  MyApp.Thunks.ConvertUnits,
  MyApp.Thunks.FormatResult
]

Jido.Operation.run(workflow, %{width: 5, height: 3}, %{from_unit: "meters", to_unit: "feet"})
```

## Error Handling

Jido provides comprehensive error handling. Thunks can return `{:error, reason}` tuples, which will be propagated through the chain:

```elixir
defmodule MyApp.Thunks.ValidateInput do
  use Jido.Operation.Thunk,
    name: "validate_input",
    schema: [
      value: [type: :integer, required: true]
    ]

  @impl true
  def run(%{value: value}, _context) when value > 0 do
    {:ok, %{value: value}}
  end

  def run(_params, _context) do
    {:error, "Input must be a positive integer"}
  end
end

result = Jido.Operation.run([ValidateInput, CalculateArea], %{value: -5})
# => {:error, "Input must be a positive integer"}
```

## Testing

Jido includes utilities for testing your Thunks:

```elixir
defmodule MyApp.Thunks.CalculateAreaTest do
  use ExUnit.Case
  alias MyApp.Thunks.CalculateArea

  test "calculates area correctly" do
    assert {:ok, %{area: 15, unit: "meters"}} ==
             Jido.Operation.run(CalculateArea, %{width: 5, height: 3}, %{unit: "meters"})
  end
end
```

## Learn More

- [Full Documentation](https://hexdocs.pm/jido)
- [Examples](https://github.com/your-org/jido/tree/main/examples)
- [Guides](https://hexdocs.pm/jido/guides/introduction.html)

## Contributing

We appreciate any contribution to Jido. Check out our [contribution guidelines](CONTRIBUTING.md) for more information.

## License

Jido is released under the [MIT License](LICENSE.md).