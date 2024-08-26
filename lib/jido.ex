defmodule Jido do
  @moduledoc """
  Jido enables intelligent automation in Elixir, with a focus on Thunks, Operations, Sensors, Assistants, and Bots for creating dynamic and adaptive systems.

  To use Jido in your project, create a module that uses Jido:

      defmodule MyJido do
        use Jido
      end

  Then add it to your supervision tree:

      children = [
        MyJido
      ]

      Supervisor.start_link(children, strategy: :one_for_one)
  """

  @doc false
  defmacro __using__(opts) do
    quote location: :keep do
      use Supervisor

      @otp_app Keyword.get(unquote(opts), :otp_app, :jido)

      def start_link(init_arg) do
        Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
      end

      @impl true
      def init(_init_arg) do
        children = [
          # Add your child specifications here
        ]

        Supervisor.init(children, strategy: :one_for_one)
      end

      defoverridable init: 1
    end
  end

  @doc """
  Convenience function to start the Jido application.
  """
  def start(_type, _args) do
    Supervisor.start_link([], strategy: :one_for_one, name: Jido.Supervisor)
  end
end
