defmodule Emergencias.Reportes do
  @moduledoc """
  INTERFAZ (el CÓMO): arma los reportes de texto (summary, recursos críticos,
  estado de una zona) consultando varios servidores. Los cálculos (qué es
  crítico, totales recursivos) están en el dominio.
  """
  alias Emergencias.{Albergues, Familias, Inventario, Mascotas, Necesidades, Zonas}
  alias Emergencias.Dominio.{Albergue, Necesidad, Recurso, Zona}

  @doc "Resumen global de la emergencia (comando summary)."
  def resumen do
    zonas = Zonas.listar()
    recursos = Inventario.listar()
    necesidades = Necesidades.listar()
    personas = Familias.listar()
    mensajes = Familias.todos_los_mensajes()
    mascotas = Mascotas.listar()
    albergues = Albergues.listar()

    ocupacion = albergues |> Enum.map(&Albergue.ocupacion/1) |> Enum.sum()
    capacidad = albergues |> Enum.map(& &1.capacidad) |> Enum.sum()

    """
    ================= RESUMEN GLOBAL =================
    Zonas registradas: #{length(zonas)} | personas afectadas (acumulado): #{Zona.total_afectados(zonas)}

    Recursos restantes por categoría:
    #{texto_conteo(Recurso.disponible_por_categoria(recursos))}
    Necesidades por estado:
    #{texto_conteo(Enum.frequencies_by(necesidades, & &1.estado))}
    Necesidades sin cerrar por prioridad:
    #{texto_conteo(necesidades |> Enum.reject(&Necesidad.cerrada?/1) |> Enum.frequencies_by(& &1.prioridad))}
    Personas por estado (localizadas: #{Enum.count(personas, &(&1.estado == :localizada))}):
    #{texto_conteo(Enum.frequencies_by(personas, & &1.estado))}
    Mensajes a familiares:
    #{texto_conteo(Enum.frequencies_by(mensajes, & &1.estado))}
    Reportes de mascotas:
    #{texto_conteo(Enum.frequencies_by(mascotas, fn m -> "#{m.tipo}/#{m.estado}" end))}
    Albergues: #{length(albergues)} | ocupación total #{ocupacion}/#{capacidad}
    ==================================================
    """
  end

  @doc "Recursos críticos (la regla está en Dominio.Recurso.criticos/2)."
  def recursos_criticos, do: Recurso.criticos(Inventario.listar(), Necesidades.listar())

  @doc "Información de una zona: árbol recursivo, estadísticas y lo que tiene asociado."
  def estado_zona(codigo) do
    case Zonas.obtener(codigo) do
      {:ok, zona} ->
        estadisticas = Zona.estadisticas(zona)
        necesidades = Necesidades.listar([{:zona, codigo}])
        recursos = Inventario.listar([{:zona, codigo}])
        albergues = Enum.filter(Albergues.listar(), &(&1.zona == codigo))
        personas = Familias.buscar([{:zona, codigo}])
        mascotas = Mascotas.listar([{:zona, codigo}])

        texto =
          """
          #{Enum.join(Zona.arbol(zona), "\n")}

          Estadísticas acumuladas: afectados #{estadisticas.afectados_totales} | sectores #{estadisticas.sectores} | puntos de atención #{estadisticas.puntos} | sectores críticos #{estadisticas.sectores_criticos}
          Necesidades: #{length(necesidades)} (sin cerrar: #{Enum.count(necesidades, &(not Necesidad.cerrada?(&1)))})
          Recursos disponibles: #{texto_conteo_linea(Recurso.disponible_por_categoria(recursos))}
          Albergues: #{Enum.map_join(albergues, ", ", &"#{&1.codigo} #{Albergue.ocupacion(&1)}/#{&1.capacidad}")}
          Personas registradas: #{length(personas)} | Reportes de mascotas: #{length(mascotas)}
          """

        {:ok, texto}

      error ->
        error
    end
  end

  defp texto_conteo(mapa) when map_size(mapa) == 0, do: "  (sin datos)"

  defp texto_conteo(mapa) do
    mapa
    |> Enum.sort()
    |> Enum.map_join("\n", fn {clave, valor} -> "  - #{clave}: #{valor}" end)
  end

  defp texto_conteo_linea(mapa) when map_size(mapa) == 0, do: "ninguno"
  defp texto_conteo_linea(mapa), do: mapa |> Enum.sort() |> Enum.map_join(", ", fn {k, v} -> "#{k} #{v}" end)
end
