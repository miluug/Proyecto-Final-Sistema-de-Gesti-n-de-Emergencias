defmodule Emergencias.Dominio.Recurso do
  @moduledoc """
  DOMINIO (el QUÉ): recurso del inventario y sus reglas: nunca cantidades
  negativas, cómo se reparte una asignación entre varias bodegas, a dónde
  llega una transferencia y qué recursos son críticos.
  La categoría usa los mismos tipos que las necesidades.
  """
  alias Emergencias.Dominio.Necesidad

  defstruct codigo: "", nombre: "", categoria: :otra, cantidad: 0, unidad: "", ubicacion: "", zona: ""

  def categorias, do: Necesidad.tipos()

  @doc "Nueva cantidad después de un movimiento; impide cantidades negativas."
  def calcular(:entrada, actual, cantidad), do: {:ok, actual + cantidad}
  def calcular(:salida, actual, cantidad) when cantidad <= actual, do: {:ok, actual - cantidad}

  def calcular(:salida, actual, cantidad),
    do: {:error, "No hay suficiente inventario: disponible #{actual}, solicitado #{cantidad}"}

  @doc "Suma RECURSIVA de las cantidades disponibles de una lista de recursos."
  def total_disponible([]), do: 0
  def total_disponible([recurso | resto]), do: recurso.cantidad + total_disponible(resto)

  @doc """
  Reparte RECURSIVAMENTE la cantidad pedida entre varios recursos de la misma
  categoría (por ejemplo, 2 bodegas de agua en la misma zona).
  Retorna la lista [{codigo, cantidad_tomada}].
  """
  def repartir(_candidatos, 0, tomados), do: Enum.reverse(tomados)
  def repartir([], _faltante, tomados), do: Enum.reverse(tomados)

  def repartir([recurso | resto], faltante, tomados) do
    tomado = min(recurso.cantidad, faltante)
    repartir(resto, faltante - tomado, [{recurso.codigo, tomado} | tomados])
  end

  @doc "Recursos que se pueden usar para una asignación: misma categoría y zona, con existencias."
  def candidatos(recursos, categoria, zona) do
    recursos
    |> Enum.filter(&(&1.categoria == categoria and &1.zona == zona and &1.cantidad > 0))
    |> Util2.ordenar(:asc, & &1.codigo)
  end

  @doc "Regla de asignación: si alcanza, retorna {:ok, [{codigo, cantidad}]}."
  def planear_toma(candidatos, categoria, cantidad, zona) do
    disponible = total_disponible(candidatos)

    cond do
      not (is_integer(cantidad) and cantidad > 0) ->
        {:error, "La cantidad debe ser mayor que cero"}

      disponible < cantidad ->
        {:error, "Inventario insuficiente de #{categoria} en la zona #{zona}: se solicitan #{cantidad} y solo hay #{disponible}"}

      true ->
        {:ok, repartir(candidatos, cantidad, [])}
    end
  end

  def validar_transferencia(recurso, origen, destino) do
    cond do
      recurso.ubicacion != origen ->
        {:error, "El recurso #{recurso.codigo} está en '#{recurso.ubicacion}', no en '#{origen}'"}

      origen == destino ->
        {:error, "El origen y el destino deben ser diferentes"}

      true ->
        :ok
    end
  end

  @doc """
  Si en el destino ya hay un recurso de la misma categoría, la transferencia
  se suma allí; si no, se crea uno nuevo con código CODIGO-DESTINO.
  """
  def recurso_destino(recursos, recurso, destino, zona) do
    case Enum.find(recursos, &(&1.categoria == recurso.categoria and &1.ubicacion == destino)) do
      nil -> %{recurso | codigo: "#{recurso.codigo}-#{destino}", cantidad: 0, ubicacion: destino, zona: zona}
      encontrado -> encontrado
    end
  end

  def disponible_por_categoria(recursos) do
    Enum.reduce(recursos, %{}, fn r, acumulado -> Map.update(acumulado, r.categoria, r.cantidad, &(&1 + r.cantidad)) end)
  end

  @doc """
  Recursos críticos: agrupa por {categoría, zona} lo disponible y lo que falta
  por entregar a necesidades sin cerrar. Es crítico si no alcanza o está agotado.
  """
  def criticos(recursos, necesidades) do
    disponible =
      Enum.reduce(recursos, %{}, fn r, acumulado ->
        Map.update(acumulado, {r.categoria, r.zona}, r.cantidad, &(&1 + r.cantidad))
      end)

    demanda =
      necesidades
      |> Enum.reject(&Necesidad.cerrada?/1)
      |> Enum.reduce(%{}, fn n, acumulado ->
        Map.update(acumulado, {n.tipo, n.zona}, Necesidad.faltante(n), &(&1 + Necesidad.faltante(n)))
      end)

    (Map.keys(disponible) ++ Map.keys(demanda))
    |> Enum.uniq()
    |> Enum.map(fn clave -> {clave, Map.get(disponible, clave, 0), Map.get(demanda, clave, 0)} end)
    |> Enum.filter(fn {_clave, hay, falta} -> hay < falta or hay == 0 end)
    |> Util2.ordenar(:desc, fn {_clave, hay, falta} -> falta - hay end)
  end
end

defmodule Emergencias.Dominio.Movimiento do
  @moduledoc "Movimiento del inventario (historial que nunca se borra)."
  @tipos [:registro, :entrada, :salida, :asignacion, :transferencia_salida, :transferencia_entrada]

  defstruct fecha: "", tipo: :entrada, codigo: "", cantidad: 0, detalle: "", usuario: ""

  def tipos, do: @tipos
end
