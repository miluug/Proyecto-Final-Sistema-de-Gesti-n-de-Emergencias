defmodule Emergencias.Comandos do
  @moduledoc """
  INTERFAZ (el CÓMO): interpreta los comandos de texto escritos por el usuario
  y los traduce a llamadas a los servidores. No contiene reglas del negocio:
  solo convierte texto en datos, valida el formato de las entradas y muestra
  el resultado.

  Flujo de `ejecutar/2`:
    1. `tokenizar/1` (RECURSIVA) separa la línea en palabras respetando comillas.
    2. Se verifica que el comando exista y que el rol del usuario lo permita.
    3. Se separan los argumentos posicionales de las opciones clave=valor.
    4. Se VALIDAN las entradas (números, opciones, existencia de zonas...) ANTES
       de llamar al GenServer correspondiente.
    5. Se registra la actividad en la Bitácora.

  Siempre retorna {:ok, texto} o {:error, texto}; nunca lanza errores por
  situaciones esperadas.
  """
  alias Emergencias.Bitacora
  alias Emergencias.Permisos
  alias Emergencias.Dominio.Usuario
  
  # Claves que se aceptan como opciones clave=valor
  @opciones ~w(zona tipo prioridad estado categoria ubicacion especie nombre edad afectados para caracteristicas)

  @doc "Ejecuta una línea de comando en nombre de `usuario` (%Usuario{})."
  def ejecutar(linea, %Usuario{} = usuario) do
    resultado =
      case tokenizar(linea) do
        [] ->
          {:error, "Comando vacío. Escriba help para ver los comandos."}

        [comando | argumentos] ->
          comando = String.downcase(comando)

          cond do
            not Permisos.existe?(comando) ->
              {:error, "Comando desconocido '#{comando}'. Escriba help."}

            not Permisos.permitido?(usuario.tipo, comando) ->
              {:error, "Un usuario #{usuario.tipo} no puede ejecutar '#{comando}' (requiere #{Permisos.rol_minimo(comando)})."}

            true ->
              {posicionales, opciones} = separar(argumentos)
              despachar(comando, posicionales, opciones, usuario)
          end
      end

    Bitacora.registrar(usuario.usuario, linea, elem(resultado, 0))
    resultado
  end

  # Análisis de la línea

  @doc """
  Separa una línea en palabras. Lo que está entre comillas queda como una sola palabra.
  Es RECURSIVA: procesa un carácter y se llama con el resto.

      iex> tokenizar(~s(register_need agua 30 critica centro "Punto sector 3"))
      ["register_need", "agua", "30", "critica", "centro", "Punto sector 3"]
  """
  def tokenizar(linea) do
    linea
    |> to_string()
    |> String.trim()
    |> String.graphemes()
    |> tokenizar([], "", false)
  end

  # tokenizar(caracteres, palabras, palabra_actual, dentro_de_comillas?)
  defp tokenizar([], palabras, "", _comillas), do: Enum.reverse(palabras)
  defp tokenizar([], palabras, actual, _comillas), do: Enum.reverse([limpiar(actual) | palabras])
  defp tokenizar(["\"" | resto], palabras, actual, comillas), do: tokenizar(resto, palabras, actual, not comillas)
  defp tokenizar([" " | resto], palabras, "", false), do: tokenizar(resto, palabras, "", false)
  defp tokenizar([" " | resto], palabras, actual, false), do: tokenizar(resto, [limpiar(actual) | palabras], "", false)
  defp tokenizar([caracter | resto], palabras, actual, comillas), do: tokenizar(resto, palabras, actual <> caracter, comillas)

  # El separador de los archivos (|) no puede venir dentro de los datos
  defp limpiar(palabra), do: String.replace(palabra, "|", "/")

  @doc "Separa los argumentos posicionales de las opciones clave=valor (ej. zona=centro)."
  def separar(argumentos) do
    Enum.reduce(argumentos, {[], %{}}, fn argumento, {posicionales, opciones} ->
      case String.split(argumento, "=", parts: 2) do
        [clave, valor] ->
          if String.downcase(clave) in @opciones do
            {posicionales, Map.put(opciones, String.downcase(clave), valor)}
          else
            {posicionales ++ [argumento], opciones}
          end

        _ ->
          {posicionales ++ [argumento], opciones}
      end
    end)
  end

  # Si el comando existe pero los argumentos no coinciden con ninguna forma válida
  defp despachar(comando, _posicionales, _opciones, _u) do
    {:error, "Argumentos incorrectos. Uso: #{Permisos.uso(comando)}"}
  end

end
