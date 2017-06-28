defmodule Retryable.Mixfile do
  use Mix.Project

  def project do
    [
      app: :retryable,
      version: "0.2.0",
      elixir: "~> 1.3",
      build_embedded: Mix.env == :prod,
      start_permanent: Mix.env == :prod,
      deps: deps(),
      package: package()
    ]
  end

  def application do
    [
      applications: [:logger],
      mod: {Retryable.App, []}
    ]
  end

  defp deps do
    [
      {:uuid, ">= 1.1.1"},
      {:ex_doc, ">= 0.0.0", only: :dev}
    ]
  end

  defp package do
    [
      name: :retryable,
      description: "Allows you to run some code and handle any timeouts or errors, with custom retry logic, while limiting the total number of concurrent things being run via worker pools.",
      files: ["lib", "mix.exs", "README*"],
      maintainers: ["Michael Baldry"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/mikebaldry/retryable"}
    ]
  end
end
