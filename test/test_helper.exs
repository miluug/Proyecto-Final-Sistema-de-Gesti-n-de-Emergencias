# Las pruebas usan la carpeta datos_test (ver config/config.exs).
# Se ejecutan en orden (async: false) porque comparten los mismos GenServer.
ExUnit.start()

defmodule Emergencias.Ayuda do
  @moduledoc "Funciones de apoyo para las pruebas."
  alias Emergencias.Cliente

  @doc "Conecta un usuario y retorna el pid de su sesión."
  def conectar(usuario, tipo, zona) do
    {:ok, pid, _datos, _mensaje} = Cliente.conectar(usuario, "1234", tipo, zona)
    pid
  end

  @doc "Ejecuta varios comandos en una sesión y retorna la lista de resultados."
  def ejecutar_todos(pid, comandos), do: Enum.map(comandos, &Cliente.ejecutar(pid, &1))

  @doc "Espera a que el supervisor cree un proceso nuevo con ese nombre."
  def esperar_reinicio(nombre, pid_anterior) do
    case Process.whereis(nombre) do
      nil ->
        :timer.sleep(10)
        esperar_reinicio(nombre, pid_anterior)

      ^pid_anterior ->
        :timer.sleep(10)
        esperar_reinicio(nombre, pid_anterior)

      nuevo ->
        nuevo
    end
  end
end
