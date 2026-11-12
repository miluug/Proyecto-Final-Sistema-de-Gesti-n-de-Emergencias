defmodule Emergencias.Persistencia do
  @moduledoc """
  PERSISTENCIA (el CÓMO): lectura y escritura de archivos de texto plano.

  Cada registro se guarda en una línea y sus campos se separan con `|`.
  Ejemplo (recursos.txt):

      R001|agua|agua|50|litros|centro_acopio_1|centro

  Este módulo solo lee y escribe líneas; la conversión entre structs y
  campos de texto está en `Emergencias.Registros`.
  """

  @separador "|"

  @doc "Ruta completa de un archivo dentro de la carpeta de datos."
  def ruta(archivo) do
    directorio = Application.get_env(:emergencias, :directorio_datos, "datos")
    Path.join(directorio, archivo)
  end

  @doc "Sobrescribe el archivo con la lista de registros (cada registro es una lista de campos)."
  def guardar(archivo, registros) do
    ruta = ruta(archivo)
    File.mkdir_p!(Path.dirname(ruta))

    contenido = Enum.map_join(registros, "", fn campos -> Enum.join(campos, @separador) <> "\n" end)

    case File.write(ruta, contenido) do
      :ok -> :ok
      {:error, razon} -> {:error, razon}
    end
  end

  @doc "Agrega un registro al final del archivo (se usa para historiales)."
  def agregar(archivo, campos) do
    ruta = ruta(archivo)
    File.mkdir_p!(Path.dirname(ruta))

    case File.write(ruta, Enum.join(campos, @separador) <> "\n", [:append]) do
      :ok -> :ok
      {:error, razon} -> {:error, razon}
    end
  end

  @doc "Lee el archivo y devuelve una lista de registros (listas de campos). Si no existe devuelve []."
  def cargar(archivo) do
    case File.read(ruta(archivo)) do
      {:ok, contenido} ->
        contenido
        |> String.split("\n", trim: true)
        |> Enum.map(&String.trim_trailing(&1, "\r"))
        |> Enum.map(&String.split(&1, @separador))

      {:error, :enoent} ->
        []

      {:error, _razon} ->
        []
    end
  end

  @doc "Elimina un archivo de datos (se usa al reiniciar los datos en las pruebas)."
  def borrar(archivo) do
    File.rm(ruta(archivo))
    :ok
  end
end
