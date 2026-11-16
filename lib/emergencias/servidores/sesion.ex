defmodule Emergencias.Sesion do
  @moduledoc """
  Proceso de sesión de un usuario conectado. Recibe comandos por mensaje, los ejecuta y responde:
    {:ejecutar, pid_origen, linea}  -> responde {:respuesta, pid_sesion, resultado}
    :cerrar                          -> termina el proceso
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

  # Atiende un mensaje y se vuelve a llamar d(recursión)
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
  Supervisor dinámico que crea un proceso de sesión por cada usuario que se conecta.
  """
  use DynamicSupervisor

  def start_link(_opciones), do: DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)

  def iniciar_sesion(usuario), do: DynamicSupervisor.start_child(__MODULE__, {Emergencias.Sesion, usuario})

  def sesiones_activas, do: DynamicSupervisor.count_children(__MODULE__).active

  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)

end
