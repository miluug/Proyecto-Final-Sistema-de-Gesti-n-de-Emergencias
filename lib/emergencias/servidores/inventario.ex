defmodule Emergencias.Inventario do
  @moduledoc """
  SERVIDOR (el CÓMO): GenServer que guarda los recursos y el historial de
  movimientos. Las reglas (no negativos, repartir, transferencias) están en
  `Emergencias.Dominio.Recurso`.

  REGLA DE CONCURRENCIA: todas las operaciones que cambian cantidades pasan
  por este único proceso. Un GenServer atiende los mensajes de su buzón UNO A
  LA VEZ, por eso si varias solicitudes intentan tomar el mismo recurso al
  mismo tiempo, cada una ve el inventario real que dejó la anterior y nunca se
  asigna más de lo disponible.

  Estado:
      %{
        recursos: %{"R001" => %Recurso{}},
        movimientos: [%Movimiento{}]   # historial, el más reciente primero
      }
  """
  use GenServer

  alias Emergencias.{Comun, Persistencia, Registros}
  alias Emergencias.Dominio.{Movimiento, Recurso}

  @archivo_recursos "recursos.txt"
  @archivo_movimientos "movimientos.txt"

  # ---------------- API ----------------

  def start_link(_opciones), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "datos: %{codigo, nombre, categoria, cantidad, unidad, ubicacion, zona}"
  def registrar(datos, usuario), do: GenServer.call(__MODULE__, {:registrar, datos, usuario})

  def entrada(codigo, cantidad, usuario, detalle \\ "entrada de inventario"),
    do: GenServer.call(__MODULE__, {:movimiento, :entrada, codigo, cantidad, usuario, detalle})

  def salida(codigo, cantidad, usuario, detalle \\ "salida de inventario"),
    do: GenServer.call(__MODULE__, {:movimiento, :salida, codigo, cantidad, usuario, detalle})

  @doc """
  Toma `cantidad` unidades de la categoría en la zona indicada (se usa al asignar
  recursos a una necesidad). Retorna {:ok, [{codigo, cantidad_tomada}]} o {:error, mensaje}.
  """
  def tomar(categoria, cantidad, zona, referencia, usuario),
    do: GenServer.call(__MODULE__, {:tomar, categoria, cantidad, zona, referencia, usuario})

  def transferir(codigo, origen, destino, cantidad, zona_destino, usuario),
    do: GenServer.call(__MODULE__, {:transferir, codigo, origen, destino, cantidad, zona_destino, usuario})

  def obtener(codigo), do: GenServer.call(__MODULE__, {:obtener, codigo})
  def listar(filtros \\ []), do: GenServer.call(__MODULE__, {:listar, filtros})
  def historial(codigo), do: GenServer.call(__MODULE__, {:historial, codigo})
  def reiniciar, do: GenServer.call(__MODULE__, :reiniciar)

  # ---------------- Callbacks ----------------

  @impl true
  def init(:ok) do
    recursos =
      @archivo_recursos
      |> Persistencia.cargar()
      |> Enum.map(&Registros.de_campos(:recurso, &1))
      |> Map.new(fn r -> {r.codigo, r} end)

    # el archivo está en orden cronológico; en memoria el más reciente va primero
    movimientos =
      @archivo_movimientos
      |> Persistencia.cargar()
      |> Enum.map(&Registros.de_campos(:movimiento, &1))
      |> Enum.reverse()

    {:ok, %{recursos: recursos, movimientos: movimientos}}
  end

  @impl true
  def handle_call({:registrar, datos, usuario}, _from, estado) do
    cond do
      Map.has_key?(estado.recursos, datos.codigo) ->
        {:reply, {:error, "Ya existe un recurso con código '#{datos.codigo}'"}, estado}

      Comun.validar_no_negativo(datos.cantidad, "La cantidad") != :ok ->
        {:reply, {:error, "La cantidad no puede ser negativa"}, estado}

      true ->
        recurso = struct(Recurso, datos)

        nuevo =
          estado
          |> poner_recurso(recurso)
          |> registrar_movimiento(:registro, recurso.codigo, recurso.cantidad, "registro en #{recurso.ubicacion}", usuario)

        guardar_recursos(nuevo)
        {:reply, {:ok, recurso}, nuevo}
    end
  end

  def handle_call({:movimiento, tipo, codigo, cantidad, usuario, detalle}, _from, estado) do
    with {:ok, recurso} <- buscar(estado, codigo),
         :ok <- Comun.validar_positivo(cantidad, "La cantidad"),
         {:ok, nueva_cantidad} <- Recurso.calcular(tipo, recurso.cantidad, cantidad) do
      recurso = %{recurso | cantidad: nueva_cantidad}

      nuevo =
        estado
        |> poner_recurso(recurso)
        |> registrar_movimiento(tipo, codigo, cantidad, detalle, usuario)

      guardar_recursos(nuevo)
      {:reply, {:ok, recurso}, nuevo}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:tomar, categoria, cantidad, zona, referencia, usuario}, _from, estado) do
    candidatos = Recurso.candidatos(Map.values(estado.recursos), categoria, zona)

    case Recurso.planear_toma(candidatos, categoria, cantidad, zona) do
      {:ok, tomados} ->
        nuevo =
          Enum.reduce(tomados, estado, fn {codigo, tomado}, acumulado ->
            recurso = Map.fetch!(acumulado.recursos, codigo)

            acumulado
            |> poner_recurso(%{recurso | cantidad: recurso.cantidad - tomado})
            |> registrar_movimiento(:asignacion, codigo, tomado, "asignado a #{referencia}", usuario)
          end)

        guardar_recursos(nuevo)
        {:reply, {:ok, tomados}, nuevo}

      error ->
        {:reply, error, estado}
    end
  end

  def handle_call({:transferir, codigo, origen, destino, cantidad, zona_destino, usuario}, _from, estado) do
    with {:ok, recurso} <- buscar(estado, codigo),
         :ok <- Recurso.validar_transferencia(recurso, origen, destino),
         :ok <- Comun.validar_positivo(cantidad, "La cantidad"),
         {:ok, restante} <- Recurso.calcular(:salida, recurso.cantidad, cantidad) do
      destino_recurso = Recurso.recurso_destino(Map.values(estado.recursos), recurso, destino, zona_destino || recurso.zona)
      detalle = "transferencia #{origen} -> #{destino}"

      nuevo =
        estado
        |> poner_recurso(%{recurso | cantidad: restante})
        |> registrar_movimiento(:transferencia_salida, codigo, cantidad, detalle, usuario)
        |> poner_recurso(%{destino_recurso | cantidad: destino_recurso.cantidad + cantidad})
        |> registrar_movimiento(:transferencia_entrada, destino_recurso.codigo, cantidad, detalle, usuario)

      guardar_recursos(nuevo)
      {:reply, {:ok, Map.fetch!(nuevo.recursos, codigo), Map.fetch!(nuevo.recursos, destino_recurso.codigo)}, nuevo}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:obtener, codigo}, _from, estado), do: {:reply, buscar(estado, codigo), estado}

  def handle_call({:listar, filtros}, _from, estado) do
    lista =
      estado.recursos
      |> Map.values()
      |> Comun.filtrar(filtros)
      |> Util2.ordenar(:asc, & &1.codigo)

    {:reply, lista, estado}
  end

  def handle_call({:historial, codigo}, _from, estado) do
    {:reply, estado.movimientos |> Enum.filter(&(&1.codigo == codigo)) |> Enum.reverse(), estado}
  end

  def handle_call(:reiniciar, _from, _estado) do
    Persistencia.borrar(@archivo_recursos)
    Persistencia.borrar(@archivo_movimientos)
    {:reply, :ok, %{recursos: %{}, movimientos: []}}
  end

  # ---------------- Auxiliares ----------------

  defp buscar(estado, codigo) do
    case Map.fetch(estado.recursos, codigo) do
      {:ok, recurso} -> {:ok, recurso}
      :error -> {:error, "No existe el recurso '#{codigo}'"}
    end
  end

  defp poner_recurso(estado, recurso), do: %{estado | recursos: Map.put(estado.recursos, recurso.codigo, recurso)}

  defp registrar_movimiento(estado, tipo, codigo, cantidad, detalle, usuario) do
    movimiento = %Movimiento{
      fecha: Comun.ahora(),
      tipo: tipo,
      codigo: codigo,
      cantidad: cantidad,
      detalle: detalle,
      usuario: usuario
    }

    Persistencia.agregar(@archivo_movimientos, Registros.a_campos(movimiento))
    %{estado | movimientos: [movimiento | estado.movimientos]}
  end

  defp guardar_recursos(estado) do
    registros =
      estado.recursos
      |> Map.values()
      |> Util2.ordenar(:asc, & &1.codigo)
      |> Enum.map(&Registros.a_campos/1)

    Persistencia.guardar(@archivo_recursos, registros)
  end
end
