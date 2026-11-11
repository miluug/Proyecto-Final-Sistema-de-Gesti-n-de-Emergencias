defmodule Emergencias.Cliente do
  @moduledoc """
  INTERFAZ (el CÓMO): punto de entrada para los usuarios (lo usan la consola, el script de
  demostración y las pruebas). Maneja connect / disconnect y envía los
  demás comandos al proceso de sesión del usuario.
  """

  alias Emergencias.{Bitacora, Sesion, SesionesSupervisor, Usuarios}

  @doc """
  connect usuario contraseña [tipo] [zona] ["nombre completo"]
  Si el usuario no existe se registra automáticamente; si existe se valida la contraseña.
  Retorna {:ok, pid_sesion, %Usuario{}, mensaje} o {:error, mensaje}.
  """
  def conectar(usuario, clave, tipo \\ nil, zona \\ nil, nombre \\ nil) do
    with {:ok, datos, forma} <- Usuarios.autenticar_o_registrar(usuario, clave, tipo, zona, nombre),
         {:ok, pid} <- SesionesSupervisor.iniciar_sesion(datos),
         :ok <- marcar_conectado(datos, pid) do
      Bitacora.registrar(datos.usuario, "connect", forma)
      {:ok, pid, datos, mensaje_conexion(datos, forma)}
    else
      {:error, mensaje} ->
        Bitacora.registrar(to_string(usuario), "connect", :error)
        {:error, mensaje}
    end
  end

  @doc "Ejecuta un comando dentro de la sesión del usuario."
  def ejecutar(pid, linea), do: Sesion.ejecutar(pid, linea)

  @doc "disconnect: cierra la sesión y marca al usuario como desconectado."
  def desconectar(pid, usuario) do
    Sesion.cerrar(pid)
    Usuarios.desconectar(usuario.usuario)
    Bitacora.registrar(usuario.usuario, "disconnect", :ok)
    {:ok, "Hasta luego, #{usuario.nombre}. Sesión cerrada."}
  end

  # Si dos conexiones del mismo usuario ocurren al mismo tiempo, solo una queda activa
  defp marcar_conectado(datos, pid) do
    case Usuarios.marcar_conectado(datos.usuario, pid) do
      :ok ->
        :ok

      error ->
        Sesion.cerrar(pid)
        error
    end
  end

  defp mensaje_conexion(usuario, :registrado),
    do: "Usuario registrado y conectado: #{usuario}"

  defp mensaje_conexion(usuario, :autenticado),
    do: "Bienvenido(a) de nuevo: #{usuario}"
    
end
