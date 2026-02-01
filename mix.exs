defmodule Ricqchet.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/ricqchet/elixir-client"

  def project do
    [
      app: :ricqchet,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: dialyzer(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url,
      name: "Ricqchet"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.14", optional: true},

      # Dev/Test tooling
      {:bypass, "~> 2.1", only: :test},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp aliases do
    [
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "dialyzer",
        "test"
      ]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:ex_unit]
    ]
  end

  defp description do
    """
    Elixir client for Ricqchet HTTP message queue service.
    Provides publish, message management, and webhook signature verification.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      files: ~w(lib docs .formatter.exs mix.exs README.md CHANGELOG.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "docs/configuration.md",
        "docs/testing.md",
        "docs/webhook-verification.md"
      ],
      groups_for_extras: [
        Guides: [
          "docs/configuration.md",
          "docs/testing.md",
          "docs/webhook-verification.md"
        ]
      ],
      groups_for_modules: [
        Client: [
          Ricqchet,
          Ricqchet.Client,
          Ricqchet.Config,
          Ricqchet.Error
        ],
        "Webhook Verification": [
          Ricqchet.Verification
        ],
        Testing: [
          Ricqchet.Testing,
          Ricqchet.Adapters.Test
        ],
        Adapters: [
          Ricqchet.Client.Adapter,
          Ricqchet.Client.HTTP
        ]
      ]
    ]
  end
end
