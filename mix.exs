defmodule Mentat.MixProject do
  use Mix.Project

  @source_url "https://github.com/keathley/mentat"
  @version "0.6.1"

  def project do
    [
      app: :mentat,
      version: @version,
      elixir: "~> 1.9",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Mentat",
      source_url: @source_url,
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:dev), do: ["lib", "test/support/test_usage.ex"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:telemetry, "~> 0.4"},
      {:norm, "~> 0.12"},
      {:oath, "~> 0.1"},

      {:credo, "~> 1.3.1", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.1", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.19", only: [:dev, :test]},
      {:propcheck, "~> 1.3", only: [:dev, :test]},
    ]
  end

  defp description do
    """
    Simple caching with ttls.
    """
  end

  defp package do
    [
      name: "mentat",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  def docs do
    [
      main: "Mentat",
      source_ref: "v#{@version}",
      source_url: @source_url,
      api_reference: false,
      extra_section: []
    ]
  end
end
