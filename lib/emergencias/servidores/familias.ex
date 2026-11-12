defmodule Emergencias.Familias do
  @moduledoc """
  SERVIDOR (el CÓMO): GenServer de personas afectadas, su historial y los
  mensajes de familiares. Las reglas (estados válidos, búsqueda) están en
  `Emergencias.Dominio.Persona`.

  Estado:
      %{
        personas: %{"1094" => %Persona{}},   # clave: documento (no se repite)
        mensajes: [%Mensaje{}],              # el más reciente primero
        siguiente_persona: 1,
        siguiente_mensaje: 1
      }
  """
  use GenServer

  alias Emergencias.{Comun, Persistencia, Registros}
  alias Emergencias.Dominio.{Mensaje, Persona}

  @archivo_personas "personas.txt"
  @archivo_historial "historial_personas.txt"
  @archivo_mensajes "mensajes.txt"

  # ---------------- API ----------------

  def start_link(_opciones), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc "datos: %{documento, nombre, edad, zona, estado}"
  def reportar(datos, usuario), do: GenServer.call(__MODULE__, {:reportar, datos, usuario})
  def cambiar_estado(documento, estado, usuario), do: GenServer.call(__MODULE__, {:cambiar_estado, documento, estado, usuario})
  def obtener(documento), do: GenServer.call(__MODULE__, {:obtener, documento})
  def existe?(documento), do: match?({:ok, _persona}, obtener(documento))
  def buscar(filtros), do: GenServer.call(__MODULE__, {:buscar, filtros})
  def listar, do: GenServer.call(__MODULE__, {:buscar, []})

  def enviar_mensaje(destinatario, contenido, remitente),
    do: GenServer.call(__MODULE__, {:enviar_mensaje, destinatario, contenido, remitente})

  def mensajes(destinatario), do: GenServer.call(__MODULE__, {:mensajes, destinatario})
  def todos_los_mensajes, do: GenServer.call(__MODULE__, :todos_los_mensajes)
  def marcar_mensaje(id, estado), do: GenServer.call(__MODULE__, {:marcar_mensaje, id, estado})
  def reiniciar, do: GenServer.call(__MODULE__, :reiniciar)

  # ---------------- Callbacks ----------------

  @impl true
  def init(:ok) do
    personas =
      @archivo_personas
      |> Persistencia.cargar()
      |> Enum.map(&Registros.de_campos(:persona, &1))
      |> Map.new(fn p -> {p.documento, p} end)

    # se agrega a cada persona su historial (archivo en orden cronológico)
    personas =
      @archivo_historial
      |> Persistencia.cargar()
      |> Enum.reduce(personas, fn [documento, fecha, anterior, nuevo, usuario], acumulado ->
        case Map.fetch(acumulado, documento) do
          {:ok, persona} ->
            cambio = {fecha, Comun.atomo(anterior, Persona.estados()), Comun.atomo(nuevo, Persona.estados()), usuario}
            Map.put(acumulado, documento, %{persona | historial: [cambio | persona.historial]})

          :error ->
            acumulado
        end
      end)

    mensajes =
      @archivo_mensajes
      |> Persistencia.cargar()
      |> Enum.map(&Registros.de_campos(:mensaje, &1))
      |> Enum.reverse()

    {:ok,
     %{
       personas: personas,
       mensajes: mensajes,
       siguiente_persona: personas |> Map.values() |> Enum.map(& &1.id) |> Comun.siguiente_numero("P"),
       siguiente_mensaje: mensajes |> Enum.map(& &1.id) |> Comun.siguiente_numero("M")
     }}
  end

  @impl true
  def handle_call({:reportar, datos, usuario}, _from, estado) do
    if Map.has_key?(estado.personas, datos.documento) do
      {:reply, {:error, "Ya existe una persona con documento '#{datos.documento}' (use update_person para cambiar su estado)"},
       estado}
    else
      persona =
        struct(Persona, datos)
        |> Map.merge(%{id: Comun.generar_id("P", estado.siguiente_persona), estado: :sin_informacion, historial: []})
        |> cambiar_y_registrar(datos.estado, usuario)

      nuevo = %{
        estado
        | personas: Map.put(estado.personas, persona.documento, persona),
          siguiente_persona: estado.siguiente_persona + 1
      }

      guardar_personas(nuevo)
      {:reply, {:ok, persona}, nuevo}
    end
  end

  def handle_call({:cambiar_estado, documento, nuevo_estado, usuario}, _from, estado) do
    with {:ok, persona} <- buscar_persona(estado, documento),
         :ok <- Persona.validar_transicion(persona, nuevo_estado) do
      actualizada = cambiar_y_registrar(persona, nuevo_estado, usuario)
      nuevo = %{estado | personas: Map.put(estado.personas, documento, actualizada)}
      guardar_personas(nuevo)
      {:reply, {:ok, actualizada}, nuevo}
    else
      error -> {:reply, error, estado}
    end
  end

  def handle_call({:obtener, documento}, _from, estado), do: {:reply, buscar_persona(estado, documento), estado}

  def handle_call({:buscar, filtros}, _from, estado) do
    resultado =
      estado.personas
      |> Map.values()
      |> Persona.buscar(filtros)
      |> Util2.ordenar(:asc, & &1.id)

    {:reply, resultado, estado}
  end

  def handle_call({:enviar_mensaje, destinatario, contenido, remitente}, _from, estado) do
    mensaje = %Mensaje{
      id: Comun.generar_id("M", estado.siguiente_mensaje),
      fecha: Comun.ahora(),
      remitente: remitente,
      destinatario: destinatario,
      contenido: contenido,
      estado: :pendiente
    }

    Persistencia.agregar(@archivo_mensajes, Registros.a_campos(mensaje))
    nuevo = %{estado | mensajes: [mensaje | estado.mensajes], siguiente_mensaje: estado.siguiente_mensaje + 1}
    {:reply, {:ok, mensaje}, nuevo}
  end

  def handle_call({:mensajes, destinatario}, _from, estado) do
    {:reply, estado.mensajes |> Enum.filter(&(&1.destinatario == destinatario)) |> Enum.reverse(), estado}
  end

  def handle_call(:todos_los_mensajes, _from, estado), do: {:reply, Enum.reverse(estado.mensajes), estado}

  def handle_call({:marcar_mensaje, id, nuevo_estado}, _from, estado) do
    id = String.upcase(id)

    case Enum.find(estado.mensajes, &(&1.id == id)) do
      nil ->
        {:reply, {:error, "No existe el mensaje '#{id}'"}, estado}

      mensaje ->
        actualizado = %{mensaje | estado: nuevo_estado}
        mensajes = Enum.map(estado.mensajes, fn m -> if m.id == id, do: actualizado, else: m end)
        Persistencia.guardar(@archivo_mensajes, mensajes |> Enum.reverse() |> Enum.map(&Registros.a_campos/1))
        {:reply, {:ok, actualizado}, %{estado | mensajes: mensajes}}
    end
  end

  def handle_call(:reiniciar, _from, _estado) do
    Enum.each([@archivo_personas, @archivo_historial, @archivo_mensajes], &Persistencia.borrar/1)
    {:reply, :ok, %{personas: %{}, mensajes: [], siguiente_persona: 1, siguiente_mensaje: 1}}
  end

  # ---------------- Auxiliares ----------------

  # Aplica la regla del dominio y guarda el cambio en el archivo de historial
  defp cambiar_y_registrar(persona, nuevo_estado, usuario) do
    fecha = Comun.ahora()
    Persistencia.agregar(@archivo_historial, [persona.documento, fecha, persona.estado, nuevo_estado, usuario])
    Persona.cambiar_estado(persona, nuevo_estado, fecha, usuario)
  end

  defp buscar_persona(estado, documento) do
    case Map.fetch(estado.personas, documento) do
      {:ok, persona} -> {:ok, persona}
      :error -> {:error, "No existe una persona con documento '#{documento}'"}
    end
  end

  defp guardar_personas(estado) do
    registros =
      estado.personas
      |> Map.values()
      |> Util2.ordenar(:asc, & &1.id)
      |> Enum.map(&Registros.a_campos/1)

    Persistencia.guardar(@archivo_personas, registros)
  end
end
