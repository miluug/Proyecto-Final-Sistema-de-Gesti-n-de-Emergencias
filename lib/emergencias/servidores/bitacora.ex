defmodule Emergencias.Bitacora do
  @moduledoc """
  SERVIDOR (el CÓMO): PROCESO INDEPENDIENTE (sin GenServer) que registra la actividad de cada usuario.

  Se crea con `spawn_link` y funciona con un ciclo RECURSIVO de `receive`:
  recibe mensajes, los atiende y se vuelve a llamar a sí mismo.
  Está registrado con el nombre `Emergencias.Bitacora` y lo vigila el
  supervisor principal: si falla, se crea un proceso nuevo.

  Mensajes que entiende:
    {:registrar, usuario, accion, resultado}   (asíncrono, no responde)
    {:consultar, pid_origen, usuario | nil}    (responde {:actividad, registros})
    {:reiniciar, pid_origen}                   (responde :reiniciada)
  """
  alias Emergencias.{Comun, Persistencia}

  @archivo "actividad.txt"

  def child_spec(_argumento) do
    %{id: __MODULE__, start: {__MODULE__, :start_link, []}}
  end

  def start_link do
    pid = spawn_link(fn -> ciclo() end)
    Process.register(pid, __MODULE__)
    {:ok, pid}
  end

  # ---------------- API (paso de mensajes) ----------------

  def registrar(usuario, accion, resultado) do
    enviar({:registrar, usuario, accion, resultado})
  end

  def consultar(usuario \\ nil) do
    enviar({:consultar, self(), usuario})

    receive do
      {:actividad, registros} -> registros
    after
      5_000 -> []
    end
  end

  def reiniciar do
    enviar({:reiniciar, self()})

    receive do
      :reiniciada -> :ok
    after
      5_000 -> :ok
    end
  end

  defp enviar(mensaje) do
    case Process.whereis(__MODULE__) do
      nil -> :error
      pid -> send(pid, mensaje)
    end
  end

  # ---------------- Ciclo recursivo del proceso ----------------

  defp ciclo do
    receive do
      {:registrar, usuario, accion, resultado} ->
        accion_limpia = accion |> to_string() |> String.replace("|", "/")
        Persistencia.agregar(@archivo, [Comun.ahora(), usuario, resultado, accion_limpia])
        ciclo()

      {:consultar, origen, usuario} ->
        registros =
          @archivo
          |> Persistencia.cargar()
          |> Enum.filter(fn [_fecha, quien | _resto] -> usuario == nil or quien == usuario end)
          |> Enum.map(fn [fecha, quien, resultado | accion] -> "#{fecha} | #{quien} | #{resultado} | #{Enum.join(accion, "|")}" end)

        send(origen, {:actividad, registros})
        ciclo()

      {:reiniciar, origen} ->
        Persistencia.borrar(@archivo)
        send(origen, :reiniciada)
        ciclo()
    end
  end
end
