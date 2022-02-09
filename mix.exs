defmodule JSONC.MixProject do
  use Mix.Project

  @source_url "https://github.com/massivefermion/jsonc"
  @jsonc_url "https://komkom.github.io/jsonc-playground"

  def project do
    [
      app: :jsonc,
      name: "jsonc",
      version: "0.2.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      package: package(),
      description: description(),
      source_url: @source_url
    ]
  end

  defp description do
    "utilities to work with jsonc, a superset of json"
  end

  defp package do
    [
      name: "jsonc",
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      exclude_patterns: ["exclude"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url, "jsonc" => @jsonc_url}
    ]
  end

  def application do
    []
  end

  defp deps do
    [{:ex_doc, "~> 0.28.0", only: :dev, runtime: false}]
  end

  defp docs do
    [
      main: JSONC,
      api_reference: false,
      source_url: @source_url,
      source_ref: "main",
      extras: ["LICENSE", "README.md"],
      logo: "logo.png"
    ]
  end
end
