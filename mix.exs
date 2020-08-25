defmodule Mentat.MixProject do
  use Mix.Project

  @version "0.4.1"

  def project do
    [
      app: :mentat,
      version: @version,
      elixir: "~> 1.9",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "Mentat",
      source_url: "https://github.com/keathley/mentat",
      docs: docs()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:telemetry, "~> 0.4"},
      {:nimble_options, "~> 0.2"},

      {:credo, "~> 1.3.1", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.19", only: [:dev, :test]}
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
      links: %{"GitHub" => "https://github.com/keathley/mentat"}
    ]
  end

  def docs do
    [
      source_ref: "v#{@version}",
      source_url: "https://github.com/keathley/mentat",
      main: "Mentat"
    ]
  end
end
