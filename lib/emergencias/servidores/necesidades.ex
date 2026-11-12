defmodule Emergencias.Necesidades do
  @moduledoc """
  SERVIDOR (el CÓMO): GenServer que guarda las necesidades.
  Las reglas (estados, prioridad, qué se puede asignar) están en
  `Emergencias.Dominio.Necesidad`.

  La asignación de recursos se hace COMPLETA dentro de este proceso:
  1. valida la necesidad con las reglas del dominio,
  2. pide los recursos al GenServer Inventario (que también es secuencial),
  3. actualiza la necesidad.
  Como ambos procesos atienden un mensaje a la vez, dos asignaciones simultáneas
  sobre la misma necesidad o el mismo recurso no generan inconsistencias.
  """
  use GenServer

  alias Emergencias.{Comun, Inventario, Persistencia, Registros}
  alias Emergencias.Dominio.Necesidad

  @archivo "necesidades.txt"

  # ---------------- API ----------------

  def start_link(_opciones), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "datos: %{tipo, cantidad, prioridad, zona, descripcion, asociado_a}"
  def registrar(datos, responsable), do: GenServer.call(__MODULE__, {:registrar, datos, responsable})

  def asignar_recurso(id, tipo, cantidad, usuario),
    do: GenServer.call(__MODULE__, {:asignar, id, tipo, cantidad, usuario})

  def cambiar_estado(id, nuevo_estado), do: GenServer.call(__MODULE__, {:cambiar_estado, id, nuevo_estado})
  def obtener(id), do: GenServer.call(__MODULE__, {:obtener, id})
  def listar(filtros \\ []), do: GenServer.call(__MODULE__, {:listar, filtros})
  def sin_cerrar, do: GenServer.call(__MODULE__, :sin_cerrar)
  def siguiente, do: GenServer.call(__MODULE__, :siguiente)
  def reiniciar, do: GenServer.call(__MODULE__, :reiniciar)

  # ---------------- Callbacks ----------------

  @impl true
  def init(:ok) do
    necesidades =
      @archivo
      |> Persistencia.cargar()
      |> Enum.map(&Registros.de_campos(:necesidad, &1))
      |> Map.new(fn n -> {n.id, n} end)

    {:ok, %{necesidades: necesidades, siguiente: Comun.siguiente_numero(Map.keys(necesidades), "N")}}
  end

  @impl true
  def handle_call({:registrar, datos, responsable}, _from, estado) do
    case Comun.validar_positivo(datos.cantidad, "La cantidad requerida") do
      :ok ->
        necesidad =
          struct(Necesidad, datos)
          |> Map.merge(%{
            id: Comun.generar_id("N", estado.siguiente),
            asignada: 0,
            responsable: responsable,
            estado: :pendiente,
            fecha: Comun.ahora()
          })

        nuevo = %{estado | necesidades: Map.put(estado.necesidades, necesidad.id, necesidad), siguiente: estado.siguiente + 1}
        guardar(nuevo)
        {:reply, {:ok, necesidad}, nuevo}

      error ->
        {:reply, error, estado}
    end
  end

  def handle_call({:asignar, id, tipo, cantidad, usuario}, _from, estado) do
    with {:ok, necesidad} <- buscar(estado, id),
         :ok <- Necesidad.validar_asignacion(necesidad, tipo, cantidad),
         {:ok, tomados} <- Inventario.tomar(tipo, cantidad, necesidad.zona, necesidad.id, usuario) do
      actualizada = Necesidad.asignar(necesidad, cantidad)
      nuevo = %{estado | necesidades: Map.put(estado.necesidades, actualizada.id, actualizada)}
      guardar(nuevo)
      {:reply, {:ok, actualizada, tomados}, nuevo}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:cambiar_estado, id, nuevo_estado}, _from, estado) do
    with {:ok, necesidad} <- buscar(estado, id),
         :ok <- Necesidad.validar_transicion(necesidad, nuevo_estado) do
      actualizada = %{necesidad | estado: nuevo_estado}
      nuevo = %{estado | necesidades: Map.put(estado.necesidades, actualizada.id, actualizada)}
      guardar(nuevo)
      {:reply, {:ok, actualizada}, nuevo}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:obtener, id}, _from, estado), do: {:reply, buscar(estado, id), estado}

  def handle_call({:listar, filtros}, _from, estado) do
    lista =
      estado.necesidades
      |> Map.values()
      |> Comun.filtrar(filtros)
      |> Necesidad.ordenar_por_prioridad()

    {:reply, lista, estado}
  end

  def handle_call(:sin_cerrar, _from, estado) do
    lista =
      estado.necesidades
      |> Map.values()
      |> Enum.reject(&Necesidad.cerrada?/1)
      |> Necesidad.ordenar_por_prioridad()

    {:reply, lista, estado}
  end

  # La prioridad se usa para SELECCIONAR la siguiente necesidad pendiente a atender
  def handle_call(:siguiente, _from, estado) do
    pendientes = estado.necesidades |> Map.values() |> Enum.filter(&(&1.estado == :pendiente))

    case Necesidad.mas_urgente(pendientes) do
      nil -> {:reply, {:error, "No hay necesidades pendientes"}, estado}
      necesidad -> {:reply, {:ok, necesidad}, estado}
    end
  end

  def handle_call(:reiniciar, _from, _estado) do
    Persistencia.borrar(@archivo)
    {:reply, :ok, %{necesidades: %{}, siguiente: 1}}
  end

  # ---------------- Auxiliares ----------------

  defp buscar(estado, id) do
    case Map.fetch(estado.necesidades, String.upcase(id)) do
      {:ok, necesidad} -> {:ok, necesidad}
      :error -> {:error, "No existe la necesidad '#{id}'"}
    end
  end

  defp guardar(estado) do
    registros =
      estado.necesidades
      |> Map.values()
      |> Util2.ordenar(:asc, & &1.id)
      |> Enum.map(&Registros.a_campos/1)

    Persistencia.guardar(@archivo, registros)
  end
end
