# Sector y PuntoAtencion se definen primero porque Zona usa sus structs en pattern matching.
defmodule Emergencias.Dominio.Sector do
  @moduledoc "Sector dentro de una zona."
  defstruct codigo: "", nombre: "", nivel: :medio, afectados: 0, puntos: []
end

defmodule Emergencias.Dominio.PuntoAtencion do
  @moduledoc "Punto de atención dentro de un sector (hoja del árbol)."
  defstruct codigo: "", nombre: "", afectados: 0
end

defmodule Emergencias.Dominio.Zona do
  @moduledoc """
  DOMINIO (el QUÉ): zona afectada con estructura jerárquica

      Zona -> [Sector] -> [PuntoAtencion]

  Aquí están las reglas y las funciones RECURSIVAS sobre la jerarquía:
  `total_afectados/1`, `contar_puntos/1` y `arbol/2`.
  `afectados` es lo registrado directamente en cada nivel; lo acumulado
  se calcula recursivamente.
  """
  alias Emergencias.Comun

  @niveles [:critico, :alto, :medio, :bajo]

  defstruct codigo: "", nombre: "", nivel: :medio, afectados: 0, sectores: []

  def niveles, do: @niveles

  #  Reglas para agregar elementos

  def validar_nueva(zonas_existentes, %__MODULE__{} = zona) do
    cond do
      Map.has_key?(zonas_existentes, zona.codigo) -> {:error, "Ya existe una zona con código '#{zona.codigo}'"}
      true -> Comun.validar_no_negativo(zona.afectados, "El número de afectados")
    end
  end

  @doc "Retorna la zona con el sector agregado o un error."
  def agregar_sector(%__MODULE__{} = zona, sector) do
    with :ok <- no_repetido(zona.sectores, sector.codigo, "sector"),
         :ok <- Comun.validar_no_negativo(sector.afectados, "El número de afectados") do
      {:ok, %{zona | sectores: zona.sectores ++ [sector]}}
    end
  end

  @doc "Retorna la zona con el punto agregado dentro del sector indicado o un error."
  def agregar_punto(%__MODULE__{} = zona, codigo_sector, punto) do
    with {:ok, sector} <- buscar_sector(zona, codigo_sector),
         :ok <- no_repetido(sector.puntos, punto.codigo, "punto de atención"),
         :ok <- Comun.validar_no_negativo(punto.afectados, "El número de afectados") do
      sector = %{sector | puntos: sector.puntos ++ [punto]}
      sectores = Enum.map(zona.sectores, fn s -> if s.codigo == codigo_sector, do: sector, else: s end)
      {:ok, %{zona | sectores: sectores}}
    end
  end

  #  Funciones RECURSIVAS

  @doc """
  Total de personas afectadas acumulado: lo del nodo + lo de todos sus hijos.
  Funciona con una zona, un sector, un punto o una lista de cualquiera de ellos.
  """
  def total_afectados(%__MODULE__{afectados: afectados, sectores: sectores}), do: afectados + total_afectados(sectores)
  def total_afectados(%Emergencias.Dominio.Sector{afectados: afectados, puntos: puntos}), do: afectados + total_afectados(puntos)
  def total_afectados(%Emergencias.Dominio.PuntoAtencion{afectados: afectados}), do: afectados
  def total_afectados([]), do: 0
  def total_afectados([cabeza | cola]), do: total_afectados(cabeza) + total_afectados(cola)

  @doc "Cantidad de puntos de atención (hojas del árbol)."
  def contar_puntos(%__MODULE__{sectores: sectores}), do: contar_puntos(sectores)
  def contar_puntos(%Emergencias.Dominio.Sector{puntos: puntos}), do: contar_puntos(puntos)
  def contar_puntos(%Emergencias.Dominio.PuntoAtencion{}), do: 1
  def contar_puntos([]), do: 0
  def contar_puntos([cabeza | cola]), do: contar_puntos(cabeza) + contar_puntos(cola)

  @doc "Árbol en líneas de texto con sangría según la profundidad."
  def arbol(nodo, profundidad \\ 0)

  def arbol(%__MODULE__{} = z, profundidad) do
    [
      linea(profundidad, "Zona #{z.codigo} - #{z.nombre} [#{z.nivel}] afectados: #{z.afectados} (acumulado #{total_afectados(z)})")
      | arbol(z.sectores, profundidad + 1)
    ]
  end

  def arbol(%Emergencias.Dominio.Sector{} = s, profundidad) do
    [
      linea(profundidad, "Sector #{s.codigo} - #{s.nombre} [#{s.nivel}] afectados: #{s.afectados} (acumulado #{total_afectados(s)})")
      | arbol(s.puntos, profundidad + 1)
    ]
  end

  def arbol(%Emergencias.Dominio.PuntoAtencion{} = p, profundidad) do
    [linea(profundidad, "Punto #{p.codigo} - #{p.nombre} afectados: #{p.afectados}")]
  end

  def arbol([], _profundidad), do: []
  def arbol([cabeza | cola], profundidad), do: arbol(cabeza, profundidad) ++ arbol(cola, profundidad)

  @doc "Estadísticas acumuladas de una zona."
  def estadisticas(%__MODULE__{} = zona) do
    %{
      afectados_totales: total_afectados(zona),
      sectores: length(zona.sectores),
      puntos: contar_puntos(zona),
      sectores_criticos: Enum.count(zona.sectores, &(&1.nivel == :critico))
    }
  end

  # Func Auxiliares

  defp linea(profundidad, texto), do: String.duplicate("    ", profundidad) <> texto

  defp buscar_sector(zona, codigo) do
    case Enum.find(zona.sectores, &(&1.codigo == codigo)) do
      nil -> {:error, "No existe el sector '#{codigo}' en la zona '#{zona.codigo}'"}
      sector -> {:ok, sector}
    end
  end

  defp no_repetido(lista, codigo, nombre) do
    if Enum.any?(lista, &(&1.codigo == codigo)) do
      {:error, "Ya existe un #{nombre} con código '#{codigo}'"}
    else
      :ok
    end
  end
end
