defmodule Emergencias.CLI do
  @moduledoc """
  INTERFAZ (el CÓMO): consola interactiva del sistema.

  Ejecutar con:
      mix run -e "Emergencias.CLI.main()"
  o dentro de iex -S mix:
      Emergencias.CLI.main()

  Cada consola maneja un usuario a la vez. Para tener varios usuarios
  trabajando al mismo tiempo sobre el mismo sistema se abren otras consolas
  conectadas al mismo nodo (ver README) o se ejecuta scripts/demo_concurrencia.exs.
  """
  alias Emergencias.Cliente

  def main do
    """
    =====================================================
      SISTEMA DE COORDINACIÓN Y GESTIÓN DE EMERGENCIAS
      Atención posterior a un terremoto
    =====================================================
    Conéctese con: connect usuario contraseña tipo zona ["nombre completo"]
    Tipos: ciudadano, voluntario, coordinador, administrador
    Escriba help (ya conectado) para ver los comandos y salir para terminar.
    """
    |> Util2.mostrar(:mensaje)

    ciclo(nil)
  end

  # sesion = nil (nadie conectado) o {pid_sesion, %Usuario{}}
  defp ciclo(sesion) do
    case leer(indicador(sesion)) do
      :fin ->
        cerrar(sesion)
        Util2.mostrar("Programa finalizado.", :mensaje)

      "" ->
        ciclo(sesion)

      linea when linea in ["salir", "exit"] ->
        cerrar(sesion)
        Util2.mostrar("Programa finalizado.", :mensaje)

      linea ->
        sesion
        |> procesar(linea)
        |> ciclo()
    end
  end

  defp procesar(nil, linea) do
    case Emergencias.Comandos.tokenizar(linea) do
      ["connect", usuario, clave | resto] ->
        [tipo, zona, nombre] = Enum.take(resto ++ [nil, nil, nil], 3)

        case Cliente.conectar(usuario, clave, tipo, zona, nombre) do
          {:ok, pid, datos, mensaje} ->
            Util2.mostrar(mensaje, :mensaje)
            {pid, datos}

          {:error, mensaje} ->
            Util2.mostrar("ERROR: " <> mensaje, :error)
            nil
        end

      _ ->
        Util2.mostrar("Primero debe conectarse: connect usuario contraseña tipo zona", :error)
        nil
    end
  end

  defp procesar({pid, usuario} = sesion, linea) do
    case String.split(linea) do
      ["disconnect"] ->
        {:ok, mensaje} = Cliente.desconectar(pid, usuario)
        Util2.mostrar(mensaje, :mensaje)
        nil

      ["connect" | _] ->
        Util2.mostrar("Ya hay una sesión activa (#{usuario.usuario}). Use disconnect primero.", :error)
        sesion

      _ ->
        mostrar_resultado(Cliente.ejecutar(pid, linea))
        sesion
    end
  end

  defp mostrar_resultado({:ok, texto}), do: Util2.mostrar(texto, :mensaje)
  defp mostrar_resultado({:error, texto}), do: Util2.mostrar("ERROR: " <> texto, :error)

  defp cerrar(nil), do: :ok
  defp cerrar({pid, usuario}), do: Cliente.desconectar(pid, usuario)

  defp indicador(nil), do: "\n[sin conexión]> "
  defp indicador({_pid, usuario}), do: "\n[#{usuario.usuario}@#{usuario.zona} (#{usuario.tipo})]> "

  # Se usa IO.gets directamente para detectar el fin de la entrada (:eof)
  defp leer(indicador) do
    case IO.gets(indicador) do
      :eof -> :fin
      {:error, _razon} -> :fin
      linea -> String.trim(linea)
    end
  end
end
