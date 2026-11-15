defmodule Emergencias do
  @moduledoc "Sistema Distribuido de Coordinación y Gestión de Emergencias"

  alias Emergencias.{Albergues, Bitacora, Familias, Inventario, Mascotas, Necesidades, SesionesSupervisor, Usuarios, Zonas}

  @doc "Borra todos los datos y cierra las sesiones"
  def reiniciar do
    SesionesSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.each(fn {_id, pid, _tipo, _modulos} -> DynamicSupervisor.terminate_child(SesionesSupervisor, pid) end)

    Enum.each([Usuarios, Zonas, Inventario, Necesidades, Familias, Mascotas, Albergues], fn modulo -> modulo.reiniciar() end)
    Bitacora.reiniciar()
    :ok
  end

end
