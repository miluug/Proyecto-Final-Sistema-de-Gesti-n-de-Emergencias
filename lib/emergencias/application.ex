defmodule Emergencias.Application do
  @moduledoc """
  Punto de arranque de la aplicación.

  Crea el árbol de supervisión principal (estrategia :one_for_one):
  si un proceso hijo falla, el supervisor reinicia solamente ese hijo
  y como cada GenServer vuelve a leer sus archivos de texto en `init/1`,
  el estado se recupera sin afectar a los demás componentes.
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
