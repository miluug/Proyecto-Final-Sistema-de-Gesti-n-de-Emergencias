defmodule Emergencias.Mascotas do
  @moduledoc """
  SERVIDOR (el CÓMO): GenServer de reportes de mascotas perdidas y encontradas.
  El criterio de similitud y las reglas están en `Emergencias.Dominio.Mascota`.
  """
  use GenServer

  alias Emergencias.{Comun, Persistencia, Registros}
  alias Emergencias.Dominio.Mascota

  @archivo "mascotas.txt"

  # ---------------- API ----------------

  def start_link(_opciones), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "datos: %{tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto}"
  def reportar(datos), do: GenServer.call(__MODULE__, {:reportar, datos})
  def listar(filtros \\ []), do: GenServer.call(__MODULE__, {:listar, filtros})

  @doc "Calcula las posibles coincidencias y marca esos reportes como :posible_coincidencia."
  def buscar_coincidencias, do: GenServer.call(__MODULE__, :buscar_coincidencias)

  @doc "Confirma la coincidencia y cierra (resuelve) ambos reportes."
  def confirmar(id_1, id_2), do: GenServer.call(__MODULE__, {:confirmar, id_1, id_2})
  def reiniciar, do: GenServer.call(__MODULE__, :reiniciar)

  # ---------------- Callbacks ----------------

  @impl true
  def init(:ok) do
    reportes =
      @archivo
      |> Persistencia.cargar()
      |> Enum.map(&Registros.de_campos(:mascota, &1))
      |> Map.new(fn m -> {m.id, m} end)

    {:ok, %{reportes: reportes, siguiente: Comun.siguiente_numero(Map.keys(reportes), "MAS")}}
  end

  @impl true
  def handle_call({:reportar, datos}, _from, estado) do
    reporte =
      struct(Mascota, datos)
      |> Map.merge(%{id: Comun.generar_id("MAS", estado.siguiente), estado: :activa, coincidencia: "", fecha: Comun.ahora()})

    nuevo = %{estado | reportes: Map.put(estado.reportes, reporte.id, reporte), siguiente: estado.siguiente + 1}
    guardar(nuevo)
    {:reply, {:ok, reporte}, nuevo}
  end

  def handle_call({:listar, filtros}, _from, estado) do
    {:reply, estado.reportes |> Map.values() |> Comun.filtrar(filtros) |> Util2.ordenar(:asc, & &1.id), estado}
  end

  def handle_call(:buscar_coincidencias, _from, estado) do
    abiertos = estado.reportes |> Map.values() |> Enum.reject(&(&1.estado == :resuelta))
    perdidas = Enum.filter(abiertos, &(&1.tipo == :perdida))
    encontradas = Enum.filter(abiertos, &(&1.tipo == :encontrada))

    coincidencias =
      perdidas
      |> Mascota.coincidencias(encontradas, [])
      |> Util2.ordenar(:desc, fn {_perdida, _encontrada, puntaje} -> puntaje end)

    # los reportes involucrados pasan a "posible coincidencia"
    ids = Enum.flat_map(coincidencias, fn {perdida, encontrada, _puntaje} -> [perdida.id, encontrada.id] end)

    reportes =
      Enum.reduce(ids, estado.reportes, fn id, acumulado ->
        Map.update!(acumulado, id, fn r -> %{r | estado: :posible_coincidencia} end)
      end)

    nuevo = %{estado | reportes: reportes}
    guardar(nuevo)
    {:reply, coincidencias, nuevo}
  end

  def handle_call({:confirmar, id_1, id_2}, _from, estado) do
    with {:ok, a} <- buscar(estado, id_1),
         {:ok, b} <- buscar(estado, id_2),
         :ok <- Mascota.validar_confirmacion(a, b) do
      reportes =
        estado.reportes
        |> Map.put(a.id, %{a | estado: :resuelta, coincidencia: b.id})
        |> Map.put(b.id, %{b | estado: :resuelta, coincidencia: a.id})

      nuevo = %{estado | reportes: reportes}
      guardar(nuevo)
      {:reply, {:ok, Map.fetch!(reportes, a.id), Map.fetch!(reportes, b.id)}, nuevo}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call(:reiniciar, _from, _estado) do
    Persistencia.borrar(@archivo)
    {:reply, :ok, %{reportes: %{}, siguiente: 1}}
  end

  # ---------------- Auxiliares ----------------

  defp buscar(estado, id) do
    case Map.fetch(estado.reportes, String.upcase(id)) do
      {:ok, reporte} -> {:ok, reporte}
      :error -> {:error, "No existe el reporte de mascota '#{id}'"}
    end
  end

  defp guardar(estado) do
    registros = estado.reportes |> Map.values() |> Util2.ordenar(:asc, & &1.id) |> Enum.map(&Registros.a_campos/1)
    Persistencia.guardar(@archivo, registros)
  end
end
