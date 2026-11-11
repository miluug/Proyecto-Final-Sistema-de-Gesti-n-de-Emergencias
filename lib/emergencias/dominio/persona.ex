defmodule Emergencias.Dominio.Persona do
  @moduledoc """
  DOMINIO (el QUÉ): persona afectada, sus estados válidos y cómo se busca.
  `historial` guarda los cambios de estado como tuplas
  {fecha, estado_anterior, estado_nuevo, usuario} (el más reciente primero).
  """
  alias Emergencias.Comun

  @estados [:sin_informacion, :reportada, :localizada, :trasladada, :en_albergue, :reunificada]

  @transiciones %{
    sin_informacion: [:reportada, :localizada],
    reportada: [:localizada, :trasladada, :en_albergue],
    localizada: [:trasladada, :en_albergue, :reunificada],
    trasladada: [:localizada, :en_albergue, :reunificada],
    en_albergue: [:trasladada, :reunificada],
    reunificada: []
  }

  defstruct id: "", documento: "", nombre: "", edad: nil, zona: "", estado: :sin_informacion, historial: []

  def estados, do: @estados

  def transicion_valida?(actual, nuevo), do: nuevo in Map.get(@transiciones, actual, [])

  def validar_transicion(persona, nuevo_estado) do
    if transicion_valida?(persona.estado, nuevo_estado) do
      :ok
    else
      {:error, "Transición inválida para #{persona.nombre}: #{persona.estado} -> #{nuevo_estado}"}
    end
  end

  @doc "Persona con el nuevo estado y el cambio agregado a su historial."
  def cambiar_estado(persona, nuevo_estado, fecha, usuario) do
    %{persona | estado: nuevo_estado, historial: [{fecha, persona.estado, nuevo_estado, usuario} | persona.historial]}
  end

  @doc """
  Búsqueda por nombre (parcial, sin mayúsculas), zona o estado.
  filtros: [{:nombre, "andres"}, {:zona, "centro"}]
  """
  def buscar(personas, filtros) do
    {por_nombre, otros} = Enum.split_with(filtros, fn {campo, _valor} -> campo == :nombre end)

    personas
    |> Comun.filtrar(otros)
    |> Enum.filter(fn persona ->
      Enum.all?(por_nombre, fn {:nombre, valor} ->
        String.contains?(String.downcase(persona.nombre), String.downcase(valor))
      end)
    end)
  end
end

defmodule Emergencias.Dominio.Mensaje do
  @moduledoc "Mensaje dirigido a una persona (documento) o a una familia (familia:Apellido)."
  @estados [:pendiente, :entregado]

  defstruct id: "", fecha: "", remitente: "", destinatario: "", contenido: "", estado: :pendiente

  def estados, do: @estados
end
