defmodule Emergencias.Albergues do
  @moduledoc """
  SERVIDOR (el CÓMO): GenServer de albergues. Las reglas de capacidad están
  en `Emergencias.Dominio.Albergue`. Como todos los ingresos pasan por este
  proceso (uno a la vez), dos ingresos simultáneos nunca superan la capacidad.
  """
  use GenServer

  alias Emergencias.{Persistencia, Registros}
  alias Emergencias.Dominio.Albergue

  @archivo "albergues.txt"

  # ---------------- API ----------------

  def start_link(_opciones), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def registrar(codigo, nombre, zona, capacidad),
    do: GenServer.call(__MODULE__, {:registrar, %Albergue{codigo: codigo, nombre: nombre, zona: zona, capacidad: capacidad}})

  def ingreso(codigo, documento), do: GenServer.call(__MODULE__, {:ingreso, codigo, documento})
  def salida(codigo, documento), do: GenServer.call(__MODULE__, {:salida, codigo, documento})
  def obtener(codigo), do: GenServer.call(__MODULE__, {:obtener, codigo})
  def existe?(codigo), do: match?({:ok, _albergue}, obtener(codigo))
  def listar, do: GenServer.call(__MODULE__, :listar)
  def ranking_ocupacion, do: Albergue.ranking(listar())
  def reiniciar, do: GenServer.call(__MODULE__, :reiniciar)

  # ---------------- Callbacks ----------------

  @impl true
  def init(:ok) do
    albergues =
      @archivo
      |> Persistencia.cargar()
      |> Enum.map(&Registros.de_campos(:albergue, &1))
      |> Map.new(fn a -> {a.codigo, a} end)

    {:ok, albergues}
  end

  @impl true
  def handle_call({:registrar, albergue}, _from, albergues) do
    case Albergue.validar_nuevo(albergues, albergue) do
      :ok -> guardar_y_responder(Map.put(albergues, albergue.codigo, albergue), {:ok, albergue})
      error -> {:reply, error, albergues}
    end
  end

  def handle_call({:ingreso, codigo, documento}, _from, albergues) do
    with {:ok, albergue} <- buscar(albergues, codigo),
         :ok <- Albergue.validar_ingreso(Map.values(albergues), albergue, documento) do
      actualizado = Albergue.ingresar(albergue, documento)
      guardar_y_responder(Map.put(albergues, codigo, actualizado), {:ok, actualizado})
    else
      error -> {:reply, error, albergues}
    end
  end

  def handle_call({:salida, codigo, documento}, _from, albergues) do
    with {:ok, albergue} <- buscar(albergues, codigo),
         :ok <- Albergue.validar_salida(albergue, documento) do
      actualizado = Albergue.retirar(albergue, documento)
      guardar_y_responder(Map.put(albergues, codigo, actualizado), {:ok, actualizado})
    else
      error -> {:reply, error, albergues}
    end
  end

  def handle_call({:obtener, codigo}, _from, albergues), do: {:reply, buscar(albergues, codigo), albergues}

  def handle_call(:listar, _from, albergues) do
    {:reply, albergues |> Map.values() |> Util2.ordenar(:asc, & &1.codigo), albergues}
  end

  def handle_call(:reiniciar, _from, _albergues) do
    Persistencia.borrar(@archivo)
    {:reply, :ok, %{}}
  end

  # ---------------- Auxiliares ----------------

  defp buscar(albergues, codigo) do
    case Map.fetch(albergues, codigo) do
      {:ok, albergue} -> {:ok, albergue}
      :error -> {:error, "No existe el albergue '#{codigo}'"}
    end
  end

  defp guardar_y_responder(albergues, respuesta) do
    registros = albergues |> Map.values() |> Util2.ordenar(:asc, & &1.codigo) |> Enum.map(&Registros.a_campos/1)
    Persistencia.guardar(@archivo, registros)
    {:reply, respuesta, albergues}
  end
end
