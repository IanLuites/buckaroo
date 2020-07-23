defmodule Buckaroo.MixProject do
  use Mix.Project

  def project do
    [
      app: :buckaroo,
      description: "Simple `:cowboy` (v2) webserver with support for SSE and WebSockets.",
      version: "0.3.1",
      elixir: "~> 1.7",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),

      # Docs
      name: "buckaroo",
      source_url: "https://github.com/IanLuites/buckaroo",
      homepage_url: "https://github.com/IanLuites/buckaroo",
      docs: [
        main: "readme",
        extras: ["README.md", "LICENSE.md"]
      ]
    ]
  end

  def package do
    [
      name: :buckaroo,
      maintainers: ["Ian Luites"],
      licenses: ["MIT"],
      files: [
        # Elixir
        "lib/buckaroo",
        "lib/buckaroo.ex",
        "mix.exs",
        "README*",
        "LICENSE*",
        ".formatter.exs"
      ],
      links: %{
        "GitHub" => "https://github.com/IanLuites/buckaroo"
      }
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:plug_cowboy, "~> 2.3"},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
