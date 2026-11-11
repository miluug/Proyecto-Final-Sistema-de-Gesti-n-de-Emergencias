defmodule Emergencias.Dominio.Usuario do
  @moduledoc """
  DOMINIO (el QUÉ): qué es un usuario y qué reglas cumple al registrarse
  o autenticarse. No sabe nada de procesos ni de archivos.
  """
  alias Emergencias.Comun

  @tipos [:ciudadano, :voluntario, :coordinador, :administrador]

  defstruct usuario: "", clave_hash: "", nombre: "", tipo: :ciudadano, zona: ""

  def tipos, do: @tipos

  @doc """
  Regla de autenticación: contraseña correcta y sin otra sesión activa.
  'conectados' es el conjunto (o mapa) de usuarios que ya tienen sesión.
  """
  def autenticar(%__MODULE__{} = usuario, clave, conectados) do
    cond do
      usuario.clave_hash != cifrar(to_string(clave)) ->
        {:error, "Contraseña incorrecta para '#{usuario.usuario}'"}

      Map.has_key?(conectados, usuario.usuario) ->
        {:error, "El usuario '#{usuario.usuario}' ya tiene una sesión activa"}

      true ->
        {:ok, usuario, :autenticado}
    end
  end

  @doc "Regla de registro: datos obligatorios y tipo válido."
  def crear(_usuario, _clave, nil, _zona, _nombre) do
    {:error, "Usuario nuevo: indique tipo y zona. Uso: connect usuario contraseña tipo zona [\"nombre completo\"]"}
  end

  def crear(usuario, clave, tipo, zona, nombre) do
    with {:ok, usuario} <- Comun.texto(usuario, "El nombre de usuario"),
         {:ok, clave} <- Comun.texto(clave, "La contraseña"),
         {:ok, tipo} <- Comun.opcion(tipo, @tipos, "Tipo de usuario"),
         {:ok, zona} <- Comun.texto(zona || "", "La zona principal") do
      nombre_completo = if nombre in [nil, ""], do: usuario, else: nombre

      {:ok, %__MODULE__{usuario: usuario, clave_hash: cifrar(clave), nombre: nombre_completo, tipo: tipo, zona: zona}}
    end
  end

  @doc "La contraseña no se guarda en texto plano: se guarda su hash SHA-256."
  def cifrar(clave), do: :crypto.hash(:sha256, clave) |> Base.encode16(case: :lower)
end
