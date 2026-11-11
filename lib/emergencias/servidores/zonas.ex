defmodule Emergencias.Zonas do
  @moduledoc """
  SERVIDOR (el CÓMO): GenServer que guarda las zonas %{codigo => %Zona{}}.
  Las reglas y la recursión sobre zona -> sectores -> puntos están en
  `Emergencias.Dominio.Zona`.
  """
  use GenServer

  alias Emergencias.{Persistencia, Registros}
  alias Emergencias.Dominio.{PuntoAtencion, Sector, Zona}

  @archivo "zonas.txt"

  #  API 

  def start_link(_opciones), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def registrar_zona(codigo, nombre, nivel, afectados) do
    zona = %Zona{codigo: codigo, nombre: nombre, nivel: nivel, afectados: afectados, sectores: []}
    GenServer.call(__MODULE__, {:registrar_zona, zona})
  end

  def registrar_sector(codigo_zona, codigo, nombre, nivel, afectados) do
    sector = %Sector{codigo: codigo, nombre: nombre, nivel: nivel, afectados: afectados, puntos: []}
    GenServer.call(__MODULE__, {:registrar_sector, codigo_zona, sector})
  end

  def registrar_punto(codigo_zona, codigo_sector, codigo, nombre, afectados) do
    punto = %PuntoAtencion{codigo: codigo, nombre: nombre, afectados: afectados}
    GenServer.call(__MODULE__, {:registrar_punto, codigo_zona, codigo_sector, punto})
  end

  def obtener(codigo), do: GenServer.call(__MODULE__, {:obtener, codigo})
  def existe?(codigo), do: match?({:ok, _zona}, obtener(codigo))
  def listar, do: GenServer.call(__MODULE__, :listar)
  def reiniciar, do: GenServer.call(__MODULE__, :reiniciar)

  #  Callbacks

  @impl true
  def init(:ok), do: {:ok, @archivo |> Persistencia.cargar() |> Registros.zonas_de_registros()}

  @impl true
  def handle_call({:registrar_zona, zona}, _from, zonas) do
    case Zona.validar_nueva(zonas, zona) do
      :ok -> guardar_y_responder(Map.put(zonas, zona.codigo, zona), {:ok, zona})
      error -> {:reply, error, zonas}
    end
  end

  def handle_call({:registrar_sector, codigo_zona, sector}, _from, zonas) do
    with {:ok, zona} <- buscar(zonas, codigo_zona),
         {:ok, zona} <- Zona.agregar_sector(zona, sector) do
      guardar_y_responder(Map.put(zonas, codigo_zona, zona), {:ok, sector})
    else
      error -> {:reply, error, zonas}
    end
  end

  def handle_call({:registrar_punto, codigo_zona, codigo_sector, punto}, _from, zonas) do
    with {:ok, zona} <- buscar(zonas, codigo_zona),
         {:ok, zona} <- Zona.agregar_punto(zona, codigo_sector, punto) do
      guardar_y_responder(Map.put(zonas, codigo_zona, zona), {:ok, punto})
    else
      error -> {:reply, error, zonas}
    end
  end

  def handle_call({:obtener, codigo}, _from, zonas), do: {:reply, buscar(zonas, codigo), zonas}

  def handle_call(:listar, _from, zonas) do
    {:reply, zonas |> Map.values() |> Util2.ordenar(:asc, & &1.codigo), zonas}
  end

  def handle_call(:reiniciar, _from, _zonas) do
    Persistencia.borrar(@archivo)
    {:reply, :ok, %{}}
  end

  # Func Auxiliares

  defp buscar(zonas, codigo) do
    case Map.fetch(zonas, codigo) do
      {:ok, zona} -> {:ok, zona}
      :error -> {:error, "No existe la zona '#{codigo}'"}
    end
  end

  defp guardar_y_responder(zonas, respuesta) do
    registros = zonas |> Map.values() |> Util2.ordenar(:asc, & &1.codigo) |> Registros.zonas_a_registros()
    Persistencia.guardar(@archivo, registros)
    {:reply, respuesta, zonas}
  end
end
