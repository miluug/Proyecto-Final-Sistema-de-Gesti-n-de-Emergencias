defmodule Emergencias.Usuarios do
  @moduledoc """
  SERVIDOR (el CÓMO): GenServer que guarda los usuarios y las sesiones activas.
  Las reglas de registro y autenticación están en `Emergencias.Dominio.Usuario`.

  Estado:
      %{
        usuarios: %{"laura" => %Usuario{}},     # mapa: búsqueda rápida por nombre de usuario
        conectados: %{"laura" => pid_sesion}    # usuarios con sesión abierta
      }

  Monitorea cada proceso de sesión: si una sesión termina (o falla),
  el usuario se marca como desconectado automáticamente.
  """
  use GenServer

  alias Emergencias.{Persistencia, Registros}
  alias Emergencias.Dominio.Usuario

  @archivo "usuarios.txt"

  # API

  def start_link(_opciones), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  Si el usuario existe valida la contraseña; si no existe lo registra automáticamente.
  Retorna {:ok, %Usuario{}, :autenticado | :registrado} o {:error, mensaje}.
  """
  def autenticar_o_registrar(usuario, clave, tipo \\ nil, zona \\ nil, nombre \\ nil) do
    GenServer.call(__MODULE__, {:autenticar, usuario, clave, tipo, zona, nombre})
  end

  def marcar_conectado(usuario, pid_sesion), do: GenServer.call(__MODULE__, {:conectado, usuario, pid_sesion})
  def desconectar(usuario), do: GenServer.call(__MODULE__, {:desconectar, usuario})
  def conectados, do: GenServer.call(__MODULE__, :conectados)
  def listar, do: GenServer.call(__MODULE__, :listar)
  def reiniciar, do: GenServer.call(__MODULE__, :reiniciar)

  # Callbacks
  
  @impl true
  def init(:ok) do
    usuarios =
      @archivo
      |> Persistencia.cargar()
      |> Enum.map(&Registros.de_campos(:usuario, &1))
      |> Map.new(fn u -> {u.usuario, u} end)

    {:ok, %{usuarios: usuarios, conectados: %{}}}
  end

  @impl true
  def handle_call({:autenticar, usuario, clave, tipo, zona, nombre}, _from, estado) do
    case Map.fetch(estado.usuarios, usuario) do
      {:ok, existente} ->
        {:reply, Usuario.autenticar(existente, clave, estado.conectados), estado}

      :error ->
        case Usuario.crear(usuario, clave, tipo, zona, nombre) do
          {:ok, nuevo} ->
            usuarios = Map.put(estado.usuarios, nuevo.usuario, nuevo)
            guardar(usuarios)
            {:reply, {:ok, nuevo, :registrado}, %{estado | usuarios: usuarios}}

          error ->
            {:reply, error, estado}
        end
    end
  end

  def handle_call({:conectado, usuario, pid}, _from, estado) do
    if Map.has_key?(estado.conectados, usuario) do
      {:reply, {:error, "El usuario '#{usuario}' ya tiene una sesión activa"}, estado}
    else
      Process.monitor(pid)
      {:reply, :ok, %{estado | conectados: Map.put(estado.conectados, usuario, pid)}}
    end
  end

  def handle_call({:desconectar, usuario}, _from, estado) do
    if Map.has_key?(estado.conectados, usuario) do
      {:reply, :ok, %{estado | conectados: Map.delete(estado.conectados, usuario)}}
    else
      {:reply, {:error, "El usuario '#{usuario}' no está conectado"}, estado}
    end
  end

  def handle_call(:conectados, _from, estado) do
    {:reply, estado.conectados |> Map.keys() |> MapSet.new(), estado}
  end

  def handle_call(:listar, _from, estado) do
    {:reply, estado.usuarios |> Map.values() |> Util2.ordenar(:asc, & &1.usuario), estado}
  end

  def handle_call(:reiniciar, _from, _estado) do
    Persistencia.borrar(@archivo)
    {:reply, :ok, %{usuarios: %{}, conectados: %{}}}
  end

  # Una sesión terminó: se elimina de los conectados
  @impl true
  def handle_info({:DOWN, _referencia, :process, pid, _razon}, estado) do
    conectados =
      estado.conectados
      |> Enum.reject(fn {_usuario, pid_sesion} -> pid_sesion == pid end)
      |> Map.new()

    {:noreply, %{estado | conectados: conectados}}
  end

  defp guardar(usuarios) do
    registros = usuarios |> Map.values() |> Util2.ordenar(:asc, & &1.usuario) |> Enum.map(&Registros.a_campos/1)
    Persistencia.guardar(@archivo, registros)
  end

end
