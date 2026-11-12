defmodule Emergencias.Dominio.Necesidad do
  @moduledoc """
  DOMINIO (el QUÉ): necesidad puntual, sus estados, la prioridad y las reglas para asignarle recursos. Sin procesos ni archivos.
 `cantidad` es lo requerido y `asignada` lo que ya se tomó del inventario.
  """

  @tipos [:agua, :alimentos, :medicamentos, :primeros_auxilios, :refugio, :transporte, :rescate, :otra]
  @prioridades [:critica, :alta, :media, :baja]
  @estados [:pendiente, :asignada, :en_atencion, :atendida, :cancelada]

  # Máquina de estados: transiciones válidas
  @transiciones %{
    pendiente: [:asignada, :en_atencion, :cancelada],
    asignada: [:en_atencion, :atendida, :cancelada],
    en_atencion: [:atendida, :cancelada],
    atendida: [],
    cancelada: []
  }

  defstruct id: "",
            tipo: :otra,
            descripcion: "",
            cantidad: 0,
            asignada: 0,
            zona: "",
            prioridad: :media,
            asociado_a: "",
            responsable: "",
            estado: :pendiente,
            fecha: ""

  def tipos, do: @tipos
  def prioridades, do: @prioridades
  def estados, do: @estados

  @doc "Peso numérico de la prioridad: entre mayor, más urgente."
  def peso(:critica), do: 4
  def peso(:alta), do: 3
  def peso(:media), do: 2
  def peso(:baja), do: 1

  def cerrada?(%__MODULE__{estado: estado}), do: estado in [:atendida, :cancelada]
  def transicion_valida?(actual, nuevo), do: nuevo in Map.get(@transiciones, actual, [])
  def faltante(%__MODULE__{cantidad: cantidad, asignada: asignada}), do: cantidad - asignada

  @doc "Ordena de la más urgente a la menos urgente; si empatan, la más antigua primero."
  def ordenar_por_prioridad(lista) do
    Util2.ordenar(lista, :asc, fn n -> {-peso(n.prioridad), n.id} end)
  end

  @doc """
  Selecciona RECURSIVAMENTE la necesidad más urgente de una lista
  (mayor prioridad; en empate la de menor id, es decir, la más antigua).
  """
  def mas_urgente([]), do: nil
  def mas_urgente([necesidad]), do: necesidad

  def mas_urgente([necesidad | resto]) do
    otra = mas_urgente(resto)
    if mas_urgente_que?(necesidad, otra), do: necesidad, else: otra
  end

  defp mas_urgente_que?(a, b) do
    cond do
      peso(a.prioridad) > peso(b.prioridad) -> true
      peso(a.prioridad) < peso(b.prioridad) -> false
      true -> a.id <= b.id
    end
  end

  @doc "Regla: ¿se le pueden asignar `cantidad` unidades de `tipo`?"
  def validar_asignacion(necesidad, tipo, cantidad) do
    cond do
      cerrada?(necesidad) ->
        {:error, "La necesidad #{necesidad.id} está #{necesidad.estado}: no puede consumir más recursos"}

      necesidad.estado == :en_atencion ->
        {:error, "La necesidad #{necesidad.id} ya está en atención"}

      necesidad.tipo != tipo ->
        {:error, "La necesidad #{necesidad.id} es de tipo #{necesidad.tipo}, no de #{tipo}"}

      not (is_integer(cantidad) and cantidad > 0) ->
        {:error, "La cantidad debe ser mayor que cero"}

      cantidad > faltante(necesidad) ->
        {:error, "A la necesidad #{necesidad.id} solo le faltan #{faltante(necesidad)} unidades"}

      true ->
        :ok
    end
  end

  @doc "Regla: ¿puede pasar al nuevo estado? (no se cierra dos veces)"
  def validar_transicion(necesidad, nuevo_estado) do
    cond do
      cerrada?(necesidad) ->
        {:error, "La necesidad #{necesidad.id} ya fue cerrada (#{necesidad.estado}); no se puede cerrar dos veces"}

      transicion_valida?(necesidad.estado, nuevo_estado) ->
        :ok

      true ->
        {:error, "Transición inválida: #{necesidad.estado} -> #{nuevo_estado}"}
    end
  end

  @doc "Necesidad después de recibir recursos."
  def asignar(necesidad, cantidad), do: %{necesidad | asignada: necesidad.asignada + cantidad, estado: :asignada}
end
