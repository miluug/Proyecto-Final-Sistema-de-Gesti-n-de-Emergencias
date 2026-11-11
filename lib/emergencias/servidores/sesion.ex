defmodule Emergencias.Sesion do
  @moduledoc """
  SERVIDOR (el CÓMO): PROCESO INDEPENDIENTE que representa la sesión de UN usuario conectado.

  Cada usuario conectado tiene su propio proceso (creado por el
  DynamicSupervisor `Emergencias.SesionesSupervisor`), por eso varios
  usuarios pueden ejecutar comandos al mismo tiempo, en paralelo.

  La sesión guarda los datos del usuario (nombre, rol y zona) y ejecuta
  los comandos que recibe por mensaje:
    {:ejecutar, pid_origen, linea}  -> responde {:respuesta, pid_sesion, resultado}
    :cerrar                          -> termina el proceso (disconnect)
  """
  
  alias Emergencias.Comandos

  @tiempo_espera 15_000

  # restart: :temporary -> si el usuario se desconecta, la sesión NO se vuelve a crear
  def child_spec(usuario) do
    %{
      id: {__MODULE__, usuario.usuario},
      start: {__MODULE__, :start_link, [usuario]},
      restart: :temporary
    }
  end

  def start_link(usuario) do
    {:ok, spawn_link(fn -> ciclo(usuario) end)}
  end

  @doc "Envía un comando a la sesión y espera la respuesta."
  def ejecutar(pid, linea) do
    send(pid, {:ejecutar, self(), linea})

    receive do
      {:respuesta, ^pid, resultado} -> resultado
    after
      @tiempo_espera -> {:error, "La sesión no respondió a tiempo"}
    end
  end

  def cerrar(pid), do: send(pid, :cerrar)

  # Ciclo RECURSIVO: atiende un mensaje y se vuelve a llamar con el mismo estado
  defp ciclo(usuario) do
    receive do
      {:ejecutar, origen, linea} ->
        resultado = Comandos.ejecutar(linea, usuario)
        send(origen, {:respuesta, self(), resultado})
        ciclo(usuario)

      :cerrar ->
        :ok
    end
  end
end

defmodule Emergencias.SesionesSupervisor do
  @moduledoc """
  DynamicSupervisor: crea un proceso de sesión cada vez que un usuario se
  conecta. Se usa un supervisor DINÁMICO porque no se sabe de antemano
  cuántos usuarios se van a conectar.
  """
  use DynamicSupervisor

  def start_link(_opciones), do: DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  def iniciar_sesion(usuario), do: DynamicSupervisor.start_child(__MODULE__, {Emergencias.Sesion, usuario})

  def sesiones_activas, do: DynamicSupervisor.count_children(__MODULE__).active

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

end
