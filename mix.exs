defmodule Jido.MixProject do
  use Mix.Project

  @source_url "https://github.com/jidohq/jido"
  @description "Jido enables intelligent automation in Elixir, with a focus on Thunks, Operations, Sensors, Assistants, and Bots for creating dynamic and adaptive systems."
  @version "0.5.0"

  def project do
    [
      app: :jido,
      version: @version,
      elixir: "~> 1.14",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test,
        "coveralls.github": :test,
        "test.ci": :test,
        "test.reset": :test,
        "test.setup": :test,
        "test.watch": :test
      ],

      # Hex
      package: package(),
      description: @description,

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:ex_unit],
        plt_core_path: "_build/#{Mix.env()}",
        flags: [:error_handling, :missing_return, :underspecs]
      ],

      # Docs
      name: "Jido",
      docs: [
        main: "Jido",
        # api_reference: false,
        logo: "assets/jido-logo.svg",
        source_ref: "v#{@version}",
        source_url: @source_url,
        # extra_section: "GUIDES",
        formatters: ["html"],
        extras: extras(),
        # groups_for_extras: groups_for_extras(),
        groups_for_modules: groups_for_modules(),
        skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  defp extras do
    [
      "README.md": [title: "Introduction"],
      "CHANGELOG.md": [title: "Changelog"]
    ]
  end

  # defp groups_for_extras do
  #   [
  #     Guides: ~r{guides/[^\/]+\.md},
  #     Recipes: ~r{guides/recipes/.?},
  #     Testing: ~r{guides/testing/.?},
  #     "Upgrade Guides": ~r{guides/upgrading/.*}
  #   ]
  # end

  defp groups_for_modules do
    [
      "Operation Core": [
        Jido.Operation,
        Jido.Operation.Thunk,
        Jido.Operation.Error
      ],
      "Operation Extensions": [
        Jido.Operation.Closure,
        Jido.Operation.Chain
      ]
      # Sensors: [
      #   Jido.Sensor,
      #   Jido.Sensor.Chain,
      #   Jido.Sensor.Chain.Step,
      #   Jido.Sensor.Chain.Step.Action,
      #   Jido.Sensor.Chain.Step.Action.Create,
      #   Jido.Sensor.Chain.Step.Action.Delete,
      #   Jido.Sensor.Chain.Step.Action.Update
      # ],
      # Assistants: [
      #   Jido.Assistant
      # ],
      # Agents: [
      #   Jido.Agent
      # ]
    ]
  end

  defp package do
    [
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      files: ~w(lib .formatter.exs mix.exs README* CHANGELOG* LICENSE*),
      links: %{
        Website: "https://github.com/jidohq/jido",
        Changelog: "#{@source_url}/blob/main/CHANGELOG.md",
        GitHub: @source_url
      }
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Dependencies
      {:nimble_options, "~> 1.1"},
      {:ok, "~> 2.3"},
      {:deep_merge, "~> 1.0"},
      {:telemetry, "~> 1.2"},

      # Testing
      {:ex_doc, "~> 0.34.2", only: [:dev, :test], runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.10", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:private, "~> 0.1.2", only: [:dev, :test]},
      {:mock, "~> 0.3.8", only: [:dev, :test]},

      # Publishing
      {:expublish, "~> 2.5", only: [:dev], runtime: false}

      # {:retry, "~> 0.18.0"},
      # {:libgraph, "~> 0.16.0"},
      # {:timex, "~> 3.7"},
      # {:elixir_uuid, "~> 1.2"},
      # {:phoenix_pubsub, "~> 2.1"},
      # {:typed_struct, "~> 0.3.0"},
      # {:typed_ecto_schema, "~> 0.4.1"},
      # {:mishka_developer_tools, "~> 0.1.7"},
      # {:error_message, "~> 0.3.2"},
      # {:progress_bar, "~> 3.0"},
      # {:exconstructor, "~> 1.2"},
      # {:telemetry_metrics, "~> 0.6"},
      # {:telemetry_poller, "~> 1.0"},
      # {:sobelow, "~> 0.12", only: [:dev, :test], runtime: false},
      # {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      # {:styler, "~> 0.11", only: [:dev, :test], runtime: false},
      # # Property-based testing
      # {:langchain, github: "brainlid/langchain"}
      # # {:dep_from_hexpm, "~> 0.3.0"},
      # # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp aliases do
    [
      release: [
        "cmd git tag v#{@version}",
        "cmd git push",
        "cmd git push --tags",
        "hex.publish --yes"
      ],
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "dialyzer --format dialyxir",
        "credo --all"
      ],
      "test.reset": ["ecto.drop --quiet", "test.setup"],
      "test.setup": ["ecto.create --quiet", "ecto.migrate --quiet"],
      "test.ci": [
        "format --check-formatted",
        "deps.unlock --check-unused",
        "credo --strict",
        "test --raise",
        "dialyzer"
      ]
    ]
  end
end
