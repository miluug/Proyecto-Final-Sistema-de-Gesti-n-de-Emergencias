defmodule Emergencias.Comun do
  @moduledoc """
  DOMINIO (el QUÉ): reglas generales compartidas por todos los módulos:
  validación de entradas, generación de identificadores, fecha y filtros.

  Las validaciones NO lanzan errores: retornan `{:ok, valor}` o `{:error, mensaje}`.
  """

  @doc "Fecha y hora actual en texto, ej: 2026-11-09 21:30:00"
  def ahora do
    NaiveDateTime.local_now()
    |> NaiveDateTime.truncate(:second)
    |> NaiveDateTime.to_string()
  end

  @doc "Genera un identificador como N001, P012, MAS003."
  def generar_id(prefijo, numero) do
    prefijo <> String.pad_leading(Integer.to_string(numero), 3, "0")
  end

  @doc "Siguiente número disponible a partir de los identificadores existentes."
  def siguiente_numero(ids, prefijo) do
    ids
    |> Enum.map(&String.replace_prefix(&1, prefijo, ""))
    |> Enum.map(&Integer.parse/1)
    |> Enum.filter(&match?({_numero, ""}, &1))
    |> Enum.map(fn {numero, ""} -> numero end)
    |> Enum.max(fn -> 0 end)
    |> Kernel.+(1)
  end

  # ---------------- Validaciones ----------------

  def entero(texto, campo) do
    case Integer.parse(to_string(texto)) do
      {numero, ""} -> {:ok, numero}
      _ -> {:error, "#{campo} debe ser un número entero (se recibió '#{texto}')"}
    end
  end

  def no_negativo(texto, campo) do
    case entero(texto, campo) do
      {:ok, numero} when numero >= 0 -> {:ok, numero}
      {:ok, _numero} -> {:error, "#{campo} no puede ser negativo"}
      error -> error
    end
  end

  def positivo(texto, campo) do
    case entero(texto, campo) do
      {:ok, numero} when numero > 0 -> {:ok, numero}
      {:ok, _numero} -> {:error, "#{campo} debe ser mayor que cero"}
      error -> error
    end
  end

  def texto(valor, campo) do
    limpio = valor |> to_string() |> String.trim()

    if limpio == "" do
      {:error, "#{campo} es obligatorio"}
    else
      {:ok, limpio}
    end
  end

  @doc "Valida que el texto sea una de las opciones (átomos) permitidas."
  def opcion(texto, opciones, campo) do
    buscado = texto |> to_string() |> String.downcase()

    case atomo(buscado, opciones) do
      nil -> {:error, "#{campo} inválido: '#{texto}'. Opciones: #{Enum.join(opciones, ", ")}"}
      encontrado -> {:ok, encontrado}
    end
  end

  @doc "Convierte un texto en uno de los átomos de la lista (sin crear átomos nuevos)."
  def atomo(texto, opciones) do
    Enum.find(opciones, fn opcion -> Atom.to_string(opcion) == texto end)
  end

  @doc "Valida un valor numérico ya convertido (para llamadas directas a los GenServer)."
  def validar_no_negativo(numero, _campo) when is_integer(numero) and numero >= 0, do: :ok
  def validar_no_negativo(_numero, campo), do: {:error, "#{campo} no puede ser negativo"}

  def validar_positivo(numero, _campo) when is_integer(numero) and numero > 0, do: :ok
  def validar_positivo(_numero, campo), do: {:error, "#{campo} debe ser mayor que cero"}

  # ---------------- Filtros ----------------

  @doc """
  Convierte las opciones escritas por el usuario (ej. %{"zona" => "centro"})
  en una lista de filtros [{:zona, "centro"}], solo con los campos permitidos.
  """
  def filtros(opciones, permitidos) do
    Enum.reduce_while(opciones, {:ok, []}, fn {clave, valor}, {:ok, acumulado} ->
      case atomo(clave, permitidos) do
        nil ->
          {:halt, {:error, "Filtro no permitido '#{clave}'. Use: #{Enum.join(permitidos, ", ")}"}}

        campo ->
          {:cont, {:ok, [{campo, valor} | acumulado]}}
      end
    end)
  end

  @doc "Deja solo los elementos que cumplen todos los filtros (comparación sin mayúsculas)."
  def filtrar(lista, filtros) do
    Enum.filter(lista, fn elemento -> cumple_filtros?(elemento, filtros) end)
  end

  defp cumple_filtros?(elemento, filtros) do
    Enum.all?(filtros, fn {campo, valor} ->
      elemento
      |> Map.get(campo)
      |> to_string()
      |> String.downcase() == String.downcase(to_string(valor))
    end)
  end
end
