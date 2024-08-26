defmodule Jido.Operation.Closure do
  @moduledoc """
  Provides functionality to create closures around Jido Operations (Thunks).

  This module allows for partial application of context and options to thunks,
  creating reusable operation closures that can be executed with different parameters.
  """

  alias Jido.Operation
  alias Jido.Operation.Error

  @type thunk :: Operation.thunk()
  @type params :: Operation.params()
  @type context :: Operation.context()
  @type run_opts :: Operation.run_opts()
  @type closure :: (params() -> {:ok, map()} | {:error, Error.t()})

  @doc """
  Creates a closure around a thunk with pre-applied context and options.

  ## Parameters

  - `thunk`: The thunk module to create a closure for.
  - `context`: The context to be applied to the thunk (default: %{}).
  - `opts`: The options to be applied to the thunk execution (default: []).

  ## Returns

  A function that takes params and returns the result of running the thunk.

  ## Examples

      iex> closure = Jido.Operation.Closure.closure(MyThunk, %{user_id: 123}, [timeout: 10_000])
      iex> closure.(%{input: "test"})
      {:ok, %{result: "processed test"}}

  """
  @spec closure(thunk(), context(), run_opts()) :: closure()
  def closure(thunk, context \\ %{}, opts \\ []) when is_atom(thunk) and is_list(opts) do
    fn params ->
      Operation.run(thunk, params, context, opts)
    end
  end

  @doc """
  Creates an async closure around a thunk with pre-applied context and options.

  ## Parameters

  - `thunk`: The thunk module to create an async closure for.
  - `context`: The context to be applied to the thunk (default: %{}).
  - `opts`: The options to be applied to the thunk execution (default: []).

  ## Returns

  A function that takes params and returns an async reference.

  ## Examples

      iex> async_closure = Jido.Operation.Closure.async_closure(MyThunk, %{user_id: 123}, [timeout: 10_000])
      iex> async_ref = async_closure.(%{input: "test"})
      iex> Jido.Operation.await(async_ref)
      {:ok, %{result: "processed test"}}

  """
  @spec async_closure(thunk(), context(), run_opts()) :: (params() -> Operation.async_ref())
  def async_closure(thunk, context \\ %{}, opts \\ []) when is_atom(thunk) and is_list(opts) do
    fn params ->
      Operation.run_async(thunk, params, context, opts)
    end
  end
end
