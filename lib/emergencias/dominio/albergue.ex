defmodule Emergencias.Dominio.Albergue do
  @moduledoc """
  DOMINIO (el QUÉ): albergue y sus reglas de capacidad.

  `ocupantes` es un MapSet con los documentos de las personas alojadas:
  una persona no puede quedar registrada dos veces y la ocupación actual
  es simplemente el tamaño del conjunto.
  """
  alias Emergencias.Comun

  defstruct codigo: "", nombre: "", zona: "", capacidad: 0, ocupantes: MapSet.new()

  def ocupacion(%__MODULE__{ocupantes: ocupantes}), do: MapSet.size(ocupantes)
  def cupos(%__MODULE__{capacidad: capacidad} = albergue), do: capacidad - ocupacion(albergue)

  def porcentaje(%__MODULE__{capacidad: 0}), do: 0.0
  def porcentaje(%__MODULE__{capacidad: capacidad} = albergue), do: ocupacion(albergue) * 100 / capacidad

  def validar_nuevo(existentes, albergue) do
    if Map.has_key?(existentes, albergue.codigo) do
      {:error, "Ya existe un albergue con código '#{albergue.codigo}'"}
    else
      Comun.validar_positivo(albergue.capacidad, "La capacidad")
    end
  end

  @doc "Regla de ingreso: la persona no está en otro albergue y hay cupo."
  def validar_ingreso(todos_los_albergues, albergue, documento) do
    otro = Enum.find(todos_los_albergues, &MapSet.member?(&1.ocupantes, documento))

    cond do
      otro != nil -> {:error, "La persona #{documento} ya está registrada en el albergue #{otro.codigo}"}
      cupos(albergue) <= 0 -> {:error, "El albergue #{albergue.codigo} está lleno (capacidad #{albergue.capacidad})"}
      true -> :ok
    end
  end

  def validar_salida(albergue, documento) do
    if MapSet.member?(albergue.ocupantes, documento) do
      :ok
    else
      {:error, "La persona #{documento} no está en el albergue #{albergue.codigo}"}
    end
  end

  def ingresar(albergue, documento), do: %{albergue | ocupantes: MapSet.put(albergue.ocupantes, documento)}
  def retirar(albergue, documento), do: %{albergue | ocupantes: MapSet.delete(albergue.ocupantes, documento)}

  @doc "Albergues ordenados del más ocupado (en porcentaje) al menos ocupado."
  def ranking(albergues), do: Util2.ordenar(albergues, :desc, &porcentaje/1)
end
