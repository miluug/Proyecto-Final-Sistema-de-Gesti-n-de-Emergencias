defmodule Emergencias.Dominio.Mascota do
  @moduledoc """
  DOMINIO (el QUÉ): reporte de mascota perdida o encontrada y el criterio
  de similitud definido por el equipo (máximo 100 puntos):

    - misma especie ............ 40 (si la especie es distinta el puntaje es 0)
    - mismo color .............. 25
    - mismo tamaño ............. 15
    - misma zona ............... 10
    - características en común . 5 por palabra repetida (máximo 10)

  Desde 60 puntos se considera "posible coincidencia".
  """
  @tipos [:perdida, :encontrada]
  @tamanos [:pequena, :mediana, :grande]
  @estados [:activa, :posible_coincidencia, :resuelta]
  @umbral 60

  defstruct id: "",
            tipo: :perdida,
            especie: "",
            nombre: "desconocido",
            caracteristicas: "",
            color: "",
            tamano: :mediana,
            zona: "",
            contacto: "",
            estado: :activa,
            coincidencia: "",
            fecha: ""

  def tipos, do: @tipos
  def tamanos, do: @tamanos
  def estados, do: @estados
  def umbral, do: @umbral

  @doc """
  Recorre RECURSIVAMENTE la lista de mascotas perdidas y, para cada una,
  compara contra todas las encontradas. Retorna [{perdida, encontrada, puntaje}]
  solo con los pares que alcanzan el umbral.
  """
  def coincidencias([], _encontradas, acumulado), do: acumulado

  def coincidencias([perdida | resto], encontradas, acumulado) do
    pares =
      encontradas
      |> Enum.map(fn encontrada -> {perdida, encontrada, puntaje(perdida, encontrada)} end)
      |> Enum.filter(fn {_p, _e, puntos} -> puntos >= @umbral end)

    coincidencias(resto, encontradas, acumulado ++ pares)
  end

  @doc "Puntaje de similitud entre dos reportes (0 a 100)."
  def puntaje(a, b) do
    if normalizar(a.especie) != normalizar(b.especie) do
      0
    else
      40 +
        if(normalizar(a.color) == normalizar(b.color), do: 25, else: 0) +
        if(a.tamano == b.tamano, do: 15, else: 0) +
        if(normalizar(a.zona) == normalizar(b.zona), do: 10, else: 0) +
        puntos_caracteristicas(a.caracteristicas, b.caracteristicas)
    end
  end

  def validar_confirmacion(a, b) do
    cond do
      a.estado == :resuelta or b.estado == :resuelta ->
        {:error, "Uno de los reportes ya está resuelto; no se puede cerrar dos veces"}

      a.tipo == b.tipo ->
        {:error, "Debe relacionar un reporte de mascota perdida con uno de mascota encontrada"}

      normalizar(a.especie) != normalizar(b.especie) ->
        {:error, "Las especies no coinciden (#{a.especie} / #{b.especie})"}

      true ->
        :ok
    end
  end

  # Las características se comparan como conjuntos de palabras (MapSet)
  defp puntos_caracteristicas(texto_a, texto_b) do
    comunes = MapSet.intersection(palabras(texto_a), palabras(texto_b)) |> MapSet.size()
    min(comunes * 5, 10)
  end

  defp palabras(texto) do
    texto
    |> normalizar()
    |> String.split([" ", ","], trim: true)
    |> Enum.filter(&(String.length(&1) > 2))
    |> MapSet.new()
  end

  defp normalizar(texto), do: texto |> to_string() |> String.trim() |> String.downcase()
end
