defmodule Emergencias.MixProject do
  use Mix.Project

  def project do
    [
      app: :emergencias,
      version: "1.0.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: []
    ]
  end

  # La aplicación arranca el árbol de supervisión definido en Emergencias.Application.
  # :crypto se usa para guardar las contraseñas cifradas (hash SHA-256).
  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Emergencias.Application, []}
    ]
  end
end
