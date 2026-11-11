defmodule Emergencias do
  @moduledoc """
  Sistema Distribuido de Coordinación y Gestión de Emergencias.
  Proyecto final - Programación III (Elixir) - Universidad del Quindío.

  Organización: se separa EL QUÉ (las reglas) del CÓMO (la técnica):

    * lib/emergencias/dominio/       EL QUÉ: structs y reglas puras del negocio
                                     (sin procesos, sin archivos, sin consola)
    * lib/emergencias/servidores/    EL CÓMO (concurrencia): GenServer, procesos
                                     Sesion y Bitacora, DynamicSupervisor
    * lib/emergencias/persistencia/  EL CÓMO (guardar): archivos .txt y conversión
    * lib/emergencias/interfaz/      EL CÓMO (usuario): consola, comandos, reportes
    * lib/emergencias/application.ex Supervisor principal
  """

  alias Emergencias.{Albergues, Bitacora, Familias, Inventario, Mascotas, Necesidades, SesionesSupervisor, Usuarios, Zonas}

  @doc "Borra todos los datos y cierra las sesiones (se usa en pruebas y en la demostración)."
  def reiniciar do
    SesionesSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_id, pid, _tipo, _modulos} -> DynamicSupervisor.terminate_child(SesionesSupervisor, pid) end)

    Enum.each([Usuarios, Zonas, Inventario, Necesidades, Familias, Mascotas, Albergues], fn modulo -> modulo.reiniciar() end)
    Bitacora.reiniciar()
    :ok
  end
  
end
