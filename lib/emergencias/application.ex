defmodule Emergencias.Application do
  @moduledoc """
  Arranca la aplicación y su árbol de supervisión. Si un proceso falla, el supervisor
  lo reinicia y ese proceso vuelve a leer sus datos desde el archivo.
  """

  use Application

  @impl true
  def start(_tipo, _argumentos) do
    hijos = [
      # Proceso independiente (spawn + receive) que registra la actividad
      Emergencias.Bitacora,
      # Componentes con estado (GenServer)
      Emergencias.Usuarios,
      Emergencias.Zonas,
      Emergencias.Inventario,
      Emergencias.Necesidades,
      Emergencias.Familias,
      Emergencias.Mascotas,
      Emergencias.Albergues,
      # Supervisor dinámico: un proceso de sesión por cada usuario conectado
      Emergencias.SesionesSupervisor
    ]

    Supervisor.start_link(hijos, strategy: :one_for_one, name: Emergencias.Supervisor)
  end
end
