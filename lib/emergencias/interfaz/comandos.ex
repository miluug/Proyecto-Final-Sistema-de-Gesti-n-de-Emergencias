defmodule Emergencias.Comandos do
  @moduledoc """
  INTERFAZ (el CÓMO): interpreta los comandos de texto escritos por el usuario
  y los traduce a llamadas a los servidores. No contiene reglas del negocio:
  solo convierte texto en datos, valida el formato de las entradas y muestra
  el resultado.

  Flujo de 'ejecutar/2':
    1. 'tokenizar/1' (RECURSIVA) separa la línea en palabras respetando comillas.
    2. Se verifica que el comando exista y que el rol del usuario lo permita.
    3. Se separan los argumentos posicionales de las opciones clave=valor.
    4. Se VALIDAN las entradas (números, opciones, existencia de zonas...) ANTES
       de llamar al GenServer correspondiente.
    5. Se registra la actividad en la Bitácora.

  Siempre retorna {:ok, texto} o {:error, texto}; nunca lanza errores por
  situaciones esperadas.
  """

  alias Emergencias.{Albergues, Bitacora, Comun, Familias, Inventario, Mascotas, Necesidades}
  alias Emergencias.{Formato, Permisos, Reportes, Usuarios, Zonas}
  alias Emergencias.Dominio.{Mascota, Mensaje, Necesidad, Persona, Recurso, Usuario, Zona}

  # Claves que se aceptan como opciones clave=valor
  @opciones ~w(zona tipo prioridad estado categoria ubicacion especie nombre edad afectados para caracteristicas)

  @doc "Ejecuta una línea de comando en nombre de 'usuario' (%Usuario{})."
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

  # GENERALES

  defp despachar("help", [], _opc, u) do
    {:ok, "Comandos disponibles para #{u.tipo}:\n" <> Enum.map_join(Permisos.disponibles(u.tipo), "\n", &"  #{&1}") <> "\n  disconnect"}
  end

  defp despachar("whoami", [], _opc, u), do: {:ok, "Conectado como #{u}"}

  defp despachar("summary", [], _opc, _u), do: {:ok, Reportes.resumen()}

  defp despachar("list_users", [], _opc, _u) do
    conectados = Usuarios.conectados()

    texto =
      Usuarios.listar()
      |> Enum.map(fn usuario -> if MapSet.member?(conectados, usuario.usuario), do: "#{usuario} [conectado]", else: "#{usuario}" end)
      |> then(&Formato.lista("Usuarios", &1))

    {:ok, texto}
  end

  defp despachar("activity", argumentos, _opc, _u) when length(argumentos) <= 1 do
    registros = Bitacora.consultar(List.first(argumentos))
    {:ok, Formato.lista("Actividad registrada", registros)}
  end

  # ZONAS

  defp despachar("register_zone", [codigo, nombre, nivel], opc, _u) do
    with {:ok, nivel} <- Comun.opcion(nivel, Zona.niveles(), "Nivel de afectación"),
         {:ok, afectados} <- Comun.no_negativo(Map.get(opc, "afectados", "0"), "El número de afectados"),
         {:ok, zona} <- Zonas.registrar_zona(codigo, nombre, nivel, afectados) do
      {:ok, "Zona registrada: #{zona}"}
    end
  end

  defp despachar("register_sector", [zona, codigo, nombre, nivel, afectados], _opc, _u) do
    with {:ok, nivel} <- Comun.opcion(nivel, Zona.niveles(), "Nivel de afectación"),
         {:ok, afectados} <- Comun.no_negativo(afectados, "El número de afectados"),
         {:ok, sector} <- Zonas.registrar_sector(zona, codigo, nombre, nivel, afectados) do
      {:ok, "Sector #{sector.codigo} registrado en la zona #{zona}"}
    end
  end

  defp despachar("register_point", [zona, sector, codigo, nombre, afectados], _opc, _u) do
    with {:ok, afectados} <- Comun.no_negativo(afectados, "El número de afectados"),
         {:ok, punto} <- Zonas.registrar_punto(zona, sector, codigo, nombre, afectados) do
      {:ok, "Punto de atención #{punto.codigo} registrado en #{zona}/#{sector}"}
    end
  end

  defp despachar("list_zones", [], _opc, _u) do
    zonas = Enum.map(Zonas.listar(), fn z -> "#{z} | acumulado #{Zona.total_afectados(z)}" end)
    {:ok, Formato.lista("Zonas", zonas)}
  end

  defp despachar("zone_status", [codigo], _opc, _u), do: Reportes.estado_zona(codigo)

  # NECESIDADES

  defp despachar("register_need", [tipo, cantidad, prioridad, zona | palabras], opc, u) when palabras != [] do
    with {:ok, tipo} <- Comun.opcion(tipo, Necesidad.tipos(), "Tipo de necesidad"),
         {:ok, cantidad} <- Comun.positivo(cantidad, "La cantidad requerida"),
         {:ok, prioridad} <- Comun.opcion(prioridad, Necesidad.prioridades(), "Prioridad"),
         :ok <- validar_zona(zona),
         {:ok, asociado} <- validar_asociado(Map.get(opc, "para", zona), zona) do
      datos = %{
        tipo: tipo,
        cantidad: cantidad,
        prioridad: prioridad,
        zona: zona,
        descripcion: Enum.join(palabras, " "),
        asociado_a: asociado
      }

      case Necesidades.registrar(datos, u.usuario) do
        {:ok, necesidad} -> {:ok, "Necesidad registrada: #{necesidad}"}
        error -> error
      end
    end
  end

  defp despachar("list_needs", [], opc, _u) do
    with {:ok, filtros} <- Comun.filtros(opc, [:zona, :tipo, :prioridad, :estado]) do
      {:ok, Formato.lista("Necesidades (ordenadas por prioridad)", Necesidades.listar(filtros))}
    end
  end

  defp despachar("pending_needs", [], _opc, _u) do
    {:ok, Formato.lista("Necesidades sin cerrar (ordenadas por prioridad)", Necesidades.sin_cerrar())}
  end

  defp despachar("next_need", [], _opc, _u) do
    case Necesidades.siguiente() do
      {:ok, necesidad} -> {:ok, "Siguiente necesidad a atender (mayor prioridad): #{necesidad}"}
      error -> error
    end
  end

  defp despachar("assign_resource", [id, tipo, cantidad], _opc, u) do
    with {:ok, tipo} <- Comun.opcion(tipo, Necesidad.tipos(), "Tipo de recurso"),
         {:ok, cantidad} <- Comun.positivo(cantidad, "La cantidad"),
         {:ok, necesidad, tomados} <- Necesidades.asignar_recurso(id, tipo, cantidad, u.usuario) do
      detalle = Enum.map_join(tomados, ", ", fn {codigo, tomado} -> "#{tomado} de #{codigo}" end)
      {:ok, "Asignación confirmada (#{detalle}). #{necesidad}"}
    end
  end

  defp despachar("update_need", [id, estado], _opc, _u) do
    with {:ok, estado} <- Comun.opcion(estado, Necesidad.estados(), "Estado"),
         {:ok, necesidad} <- Necesidades.cambiar_estado(id, estado) do
      {:ok, "Necesidad actualizada: #{necesidad}"}
    end
  end

  # RECURSOS

  defp despachar("register_resource", [codigo, categoria, cantidad, unidad, ubicacion], opc, u) do
    zona = Map.get(opc, "zona", u.zona)

    with {:ok, categoria} <- Comun.opcion(categoria, Recurso.categorias(), "Categoría"),
         {:ok, cantidad} <- Comun.no_negativo(cantidad, "La cantidad"),
         :ok <- validar_zona(zona) do
      datos = %{
        codigo: codigo,
        nombre: Map.get(opc, "nombre", Atom.to_string(categoria)),
        categoria: categoria,
        cantidad: cantidad,
        unidad: unidad,
        ubicacion: ubicacion,
        zona: zona
      }

      case Inventario.registrar(datos, u.usuario) do
        {:ok, recurso} -> {:ok, "Recurso registrado: #{recurso}"}
        error -> error
      end
    end
  end

  defp despachar("list_resources", [], opc, _u) do
    with {:ok, filtros} <- Comun.filtros(opc, [:categoria, :zona, :ubicacion]) do
      recursos = Inventario.listar(filtros)
      total = Enum.map_join(Recurso.disponible_por_categoria(recursos), ", ", fn {c, n} -> "#{c}: #{n}" end)
      {:ok, Formato.lista("Recursos", recursos) <> "\nTotal disponible -> #{total}"}
    end
  end

  defp despachar("resource_in", [codigo, cantidad], _opc, u) do
    with {:ok, cantidad} <- Comun.positivo(cantidad, "La cantidad"),
         {:ok, recurso} <- Inventario.entrada(codigo, cantidad, u.usuario) do
      {:ok, "Entrada registrada. #{recurso}"}
    end
  end

  defp despachar("resource_out", [codigo, cantidad], _opc, u) do
    with {:ok, cantidad} <- Comun.positivo(cantidad, "La cantidad"),
         {:ok, recurso} <- Inventario.salida(codigo, cantidad, u.usuario) do
      {:ok, "Salida registrada. #{recurso}"}
    end
  end

  defp despachar("transfer_resource", [codigo, origen, destino, cantidad], opc, u) do
    zona_destino = Map.get(opc, "zona")

    with {:ok, cantidad} <- Comun.positivo(cantidad, "La cantidad"),
         :ok <- if(zona_destino, do: validar_zona(zona_destino), else: :ok),
         {:ok, recurso_origen, recurso_destino} <-
           Inventario.transferir(codigo, origen, destino, cantidad, zona_destino, u.usuario) do
      {:ok, "Transferencia realizada.\n  Origen : #{recurso_origen}\n  Destino: #{recurso_destino}"}
    end
  end

  defp despachar("resource_history", [codigo], _opc, _u) do
    {:ok, Formato.lista("Historial de movimientos de #{codigo}", Inventario.historial(codigo))}
  end

  defp despachar("critical_resources", [], _opc, _u) do
    criticos =
      Enum.map(Reportes.recursos_criticos(), fn {{categoria, zona}, hay, falta} ->
        "#{categoria} en zona #{zona}: disponible #{hay}, demanda pendiente #{falta}"
      end)

    {:ok, Formato.lista("Recursos críticos", criticos)}
  end

  # COMUNICACIÓN ENTRE FAMILIARES

  defp despachar("report_person", [documento, nombre, zona, estado], opc, u) do
    with {:ok, documento} <- validar_documento(documento),
         {:ok, estado} <- Comun.opcion(estado, Persona.estados(), "Estado"),
         {:ok, edad} <- validar_edad(Map.get(opc, "edad")),
         :ok <- validar_zona(zona),
         {:ok, persona} <-
           Familias.reportar(%{documento: documento, nombre: nombre, edad: edad, zona: zona, estado: estado}, u.usuario) do
      {:ok, "Persona registrada: #{persona}"}
    end
  end

  defp despachar("update_person", [documento, estado], _opc, u) do
    with {:ok, estado} <- Comun.opcion(estado, Persona.estados(), "Estado"),
         {:ok, persona} <- Familias.cambiar_estado(documento, estado, u.usuario) do
      {:ok, "Estado actualizado: #{persona}"}
    end
  end

  defp despachar("find_person", [documento], _opc, _u) do
    case Familias.obtener(documento) do
      {:ok, persona} -> {:ok, "Encontrada: #{persona}"}
      error -> error
    end
  end

  defp despachar("find_person", [], opc, _u) when map_size(opc) > 0 do
    with {:ok, filtros} <- Comun.filtros(opc, [:nombre, :zona, :estado]) do
      {:ok, Formato.lista("Personas encontradas", Familias.buscar(filtros))}
    end
  end

  defp despachar("person_history", [documento], _opc, _u) do
    with {:ok, persona} <- Familias.obtener(documento) do
      cambios =
        persona.historial
        |> Enum.reverse()
        |> Enum.map(fn {fecha, anterior, nuevo, usuario} -> "#{fecha}: #{anterior} -> #{nuevo} (por #{usuario})" end)

      {:ok, "#{persona}\n" <> Formato.lista("Historial de estados", cambios)}
    end
  end

  defp despachar("send_family_message", [destinatario | palabras], _opc, u) when palabras != [] do
    with :ok <- validar_destinatario(destinatario),
         {:ok, mensaje} <- Familias.enviar_mensaje(destinatario, Enum.join(palabras, " "), u.usuario) do
      {:ok, "Mensaje guardado: #{mensaje}"}
    end
  end

  defp despachar("list_family_messages", [destinatario], _opc, _u) do
    {:ok, Formato.lista("Mensajes para #{destinatario}", Familias.mensajes(destinatario))}
  end

  defp despachar("mark_message", [id, estado], _opc, _u) do
    with {:ok, estado} <- Comun.opcion(estado, Mensaje.estados(), "Estado del mensaje"),
         {:ok, mensaje} <- Familias.marcar_mensaje(id, estado) do
      {:ok, "Mensaje actualizado: #{mensaje}"}
    end
  end

  # MASCOTAS

  defp despachar("report_pet", [tipo, especie, nombre, color, tamano, zona, contacto], opc, _u) do
    with {:ok, tipo} <- tipo_reporte(tipo),
         {:ok, especie} <- Comun.texto(especie, "La especie"),
         {:ok, tamano} <- Comun.opcion(tamano, Mascota.tamanos(), "Tamaño"),
         :ok <- validar_zona(zona) do
      datos = %{
        tipo: tipo,
        especie: String.downcase(especie),
        nombre: nombre,
        caracteristicas: Map.get(opc, "caracteristicas", ""),
        color: String.downcase(color),
        tamano: tamano,
        zona: zona,
        contacto: contacto
      }

      case Mascotas.reportar(datos) do
        {:ok, reporte} -> {:ok, "Reporte registrado: #{reporte}"}
        error -> error
      end
    end
  end

  defp despachar("list_pets", [], opc, _u) do
    with {:ok, filtros} <- Comun.filtros(opc, [:especie, :zona, :estado, :tipo]) do
      {:ok, Formato.lista("Reportes de mascotas", Mascotas.listar(filtros))}
    end
  end

  defp despachar("match_pets", [], _opc, _u) do
    coincidencias =
      Enum.map(Mascotas.buscar_coincidencias(), fn {perdida, encontrada, puntaje} ->
        "#{perdida.id} (perdida, #{perdida.nombre}) <-> #{encontrada.id} (encontrada) | puntaje #{puntaje}/100"
      end)

    {:ok, Formato.lista("Posibles coincidencias (umbral #{Mascota.umbral()})", coincidencias)}
  end

  defp despachar("confirm_match", [id_1, id_2], _opc, _u) do
    case Mascotas.confirmar(id_1, id_2) do
      {:ok, a, b} -> {:ok, "Coincidencia confirmada. Reportes cerrados:\n  #{a}\n  #{b}"}
      error -> error
    end
  end

  # ALBERGUES

  defp despachar("register_shelter", [codigo, nombre, zona, capacidad], _opc, _u) do
    with {:ok, capacidad} <- Comun.positivo(capacidad, "La capacidad"),
         :ok <- validar_zona(zona),
         {:ok, albergue} <- Albergues.registrar(codigo, nombre, zona, capacidad) do
      {:ok, "Albergue registrado: #{albergue}"}
    end
  end

  defp despachar("check_shelter", [codigo], _opc, _u) do
    with {:ok, albergue} <- Albergues.obtener(codigo) do
      recursos = Inventario.listar([{:ubicacion, codigo}])
      necesidades = Necesidades.listar([{:asociado_a, codigo}])
      ocupantes = albergue.ocupantes |> MapSet.to_list() |> Enum.sort() |> Enum.join(", ")

      {:ok,
       "#{albergue}\nPersonas alojadas: #{ocupantes}\n" <>
         Formato.lista("Recursos en el albergue", recursos) <>
         "\n" <> Formato.lista("Necesidades del albergue", necesidades)}
    end
  end

  defp despachar("list_shelters", [], _opc, _u), do: {:ok, Formato.lista("Albergues", Albergues.listar())}

  defp despachar("register_entry", [codigo, documento], _opc, u) do
    with {:ok, documento} <- validar_documento(documento),
         {:ok, albergue} <- Albergues.ingreso(codigo, documento) do
      {:ok, "Ingreso registrado. #{albergue}" <> actualizar_persona_en_albergue(documento, u)}
    end
  end

  defp despachar("register_exit", [codigo, documento], _opc, _u) do
    case Albergues.salida(codigo, documento) do
      {:ok, albergue} -> {:ok, "Salida registrada. #{albergue}"}
      error -> error
    end
  end

  defp despachar("shelter_ranking", [], _opc, _u) do
    {:ok, Formato.lista("Albergues con mayor ocupación", Albergues.ranking_ocupacion())}
  end

  # Si el comando existe pero los argumentos no coinciden con ninguna forma válida
  defp despachar(comando, _posicionales, _opciones, _u) do
    {:error, "Argumentos incorrectos. Uso: #{Permisos.uso(comando)}"}
  end

  #  Validaciones de entrada

  defp validar_zona(zona) do
    if Zonas.existe?(zona), do: :ok, else: {:error, "La zona '#{zona}' no está registrada (use register_zone)"}
  end

  # Una necesidad se asocia a la zona, a un albergue, a una persona o a una familia
  defp validar_asociado(asociado, zona) do
    cond do
      asociado == zona -> {:ok, zona}
      String.starts_with?(asociado, "familia:") -> {:ok, asociado}
      Albergues.existe?(asociado) -> {:ok, asociado}
      Familias.existe?(asociado) -> {:ok, asociado}
      true -> {:error, "'#{asociado}' no es un albergue ni una persona registrada (o use familia:apellido)"}
    end
  end

  defp validar_destinatario(destinatario) do
    cond do
      String.starts_with?(destinatario, "familia:") -> :ok
      Familias.existe?(destinatario) -> :ok
      true -> {:error, "No hay una persona registrada con documento '#{destinatario}' (o use familia:apellido)"}
    end
  end

  defp validar_documento(documento) do
    if String.contains?(documento, [",", " "]) or documento == "" do
      {:error, "Documento inválido: '#{documento}'"}
    else
      {:ok, documento}
    end
  end

  defp validar_edad(nil), do: {:ok, nil}

  defp validar_edad(texto) do
    case Comun.no_negativo(texto, "La edad") do
      {:ok, edad} when edad <= 120 -> {:ok, edad}
      {:ok, _edad} -> {:error, "La edad no es válida"}
      error -> error
    end
  end

  defp tipo_reporte(tipo) when tipo in ["lost", "perdida"], do: {:ok, :perdida}
  defp tipo_reporte(tipo) when tipo in ["found", "encontrada"], do: {:ok, :encontrada}
  defp tipo_reporte(tipo), do: {:error, "Tipo de reporte inválido '#{tipo}'. Use lost o found"}

  # Al ingresar a un albergue, si la persona está registrada su estado pasa a en_albergue
  defp actualizar_persona_en_albergue(documento, u) do
    case Familias.obtener(documento) do
      {:ok, %Persona{estado: :en_albergue}} ->
        ""

      {:ok, _persona} ->
        case Familias.cambiar_estado(documento, :en_albergue, u.usuario) do
          {:ok, persona} -> "\nEstado de la persona actualizado: #{persona}"
          {:error, mensaje} -> "\n(No se cambió el estado de la persona: #{mensaje})"
        end

      {:error, _mensaje} ->
        "\n(La persona no está registrada en el sistema de familiares)"
    end
  end
  
end
