defmodule Emergencias.Registros do
  @moduledoc """
  PERSISTENCIA (el CÓMO): convierte los structs del dominio en listas de
  campos de texto (una línea del archivo) y viceversa.

  Así el dominio no sabe cómo se guarda la información: si mañana se
  cambiara el formato de los archivos, solo se modifica este módulo.
  """
  alias Emergencias.Comun

  alias Emergencias.Dominio.{
    Albergue, Mascota, Mensaje, Movimiento, Necesidad, Persona, PuntoAtencion, Recurso, Sector, Usuario, Zona
  }

  # ---------------- struct -> campos (pattern matching por tipo de struct) ----------------

  def a_campos(%Usuario{} = u), do: [u.usuario, u.clave_hash, u.nombre, u.tipo, u.zona]

  def a_campos(%Necesidad{} = n) do
    [n.id, n.tipo, n.descripcion, n.cantidad, n.asignada, n.zona, n.prioridad, n.asociado_a, n.responsable, n.estado, n.fecha]
  end

  def a_campos(%Recurso{} = r), do: [r.codigo, r.nombre, r.categoria, r.cantidad, r.unidad, r.ubicacion, r.zona]
  def a_campos(%Movimiento{} = m), do: [m.fecha, m.tipo, m.codigo, m.cantidad, m.detalle, m.usuario]
  def a_campos(%Persona{} = p), do: [p.id, p.documento, p.nombre, p.edad || "", p.zona, p.estado]
  def a_campos(%Mensaje{} = m), do: [m.id, m.fecha, m.remitente, m.destinatario, m.contenido, m.estado]

  def a_campos(%Mascota{} = m) do
    [m.id, m.tipo, m.especie, m.nombre, m.caracteristicas, m.color, m.tamano, m.zona, m.contacto, m.estado, m.coincidencia, m.fecha]
  end

  def a_campos(%Albergue{} = a) do
    [a.codigo, a.nombre, a.zona, a.capacidad, a.ocupantes |> MapSet.to_list() |> Enum.sort() |> Enum.join(",")]
  end

  # ---------------- campos -> struct ----------------

  def de_campos(:usuario, [usuario, clave_hash, nombre, tipo, zona]) do
    %Usuario{usuario: usuario, clave_hash: clave_hash, nombre: nombre, tipo: Comun.atomo(tipo, Usuario.tipos()), zona: zona}
  end

  def de_campos(:necesidad, [id, tipo, descripcion, cantidad, asignada, zona, prioridad, asociado_a, responsable, estado, fecha]) do
    %Necesidad{
      id: id,
      tipo: Comun.atomo(tipo, Necesidad.tipos()),
      descripcion: descripcion,
      cantidad: String.to_integer(cantidad),
      asignada: String.to_integer(asignada),
      zona: zona,
      prioridad: Comun.atomo(prioridad, Necesidad.prioridades()),
      asociado_a: asociado_a,
      responsable: responsable,
      estado: Comun.atomo(estado, Necesidad.estados()),
      fecha: fecha
    }
  end

  def de_campos(:recurso, [codigo, nombre, categoria, cantidad, unidad, ubicacion, zona]) do
    %Recurso{
      codigo: codigo,
      nombre: nombre,
      categoria: Comun.atomo(categoria, Recurso.categorias()),
      cantidad: String.to_integer(cantidad),
      unidad: unidad,
      ubicacion: ubicacion,
      zona: zona
    }
  end

  def de_campos(:movimiento, [fecha, tipo, codigo, cantidad, detalle, usuario]) do
    %Movimiento{
      fecha: fecha,
      tipo: Comun.atomo(tipo, Movimiento.tipos()),
      codigo: codigo,
      cantidad: String.to_integer(cantidad),
      detalle: detalle,
      usuario: usuario
    }
  end

  def de_campos(:persona, [id, documento, nombre, edad, zona, estado]) do
    %Persona{
      id: id,
      documento: documento,
      nombre: nombre,
      edad: if(edad == "", do: nil, else: String.to_integer(edad)),
      zona: zona,
      estado: Comun.atomo(estado, Persona.estados()),
      historial: []
    }
  end

  def de_campos(:mensaje, [id, fecha, remitente, destinatario, contenido, estado]) do
    %Mensaje{
      id: id,
      fecha: fecha,
      remitente: remitente,
      destinatario: destinatario,
      contenido: contenido,
      estado: Comun.atomo(estado, Mensaje.estados())
    }
  end

  def de_campos(:mascota, [id, tipo, especie, nombre, caracteristicas, color, tamano, zona, contacto, estado, coincidencia, fecha]) do
    %Mascota{
      id: id,
      tipo: Comun.atomo(tipo, Mascota.tipos()),
      especie: especie,
      nombre: nombre,
      caracteristicas: caracteristicas,
      color: color,
      tamano: Comun.atomo(tamano, Mascota.tamanos()),
      zona: zona,
      contacto: contacto,
      estado: Comun.atomo(estado, Mascota.estados()),
      coincidencia: coincidencia,
      fecha: fecha
    }
  end

  def de_campos(:albergue, [codigo, nombre, zona, capacidad, ocupantes]) do
    %Albergue{
      codigo: codigo,
      nombre: nombre,
      zona: zona,
      capacidad: String.to_integer(capacidad),
      ocupantes: ocupantes |> String.split(",", trim: true) |> MapSet.new()
    }
  end

  # ---------------- Zonas: estructura jerárquica en 3 tipos de línea ----------------
  #   ZONA|codigo|nombre|nivel|afectados
  #   SECTOR|zona|codigo|nombre|nivel|afectados
  #   PUNTO|zona|sector|codigo|nombre|afectados

  def zonas_a_registros(zonas) do
    Enum.flat_map(zonas, fn z ->
      [
        ["ZONA", z.codigo, z.nombre, z.nivel, z.afectados]
        | Enum.flat_map(z.sectores, fn s ->
            [
              ["SECTOR", z.codigo, s.codigo, s.nombre, s.nivel, s.afectados]
              | Enum.map(s.puntos, fn p -> ["PUNTO", z.codigo, s.codigo, p.codigo, p.nombre, p.afectados] end)
            ]
          end)
      ]
    end)
  end

  @doc "Reconstruye el mapa %{codigo => %Zona{}} a partir de las líneas del archivo."
  def zonas_de_registros(registros), do: Enum.reduce(registros, %{}, &agregar_registro/2)

  defp agregar_registro(["ZONA", codigo, nombre, nivel, afectados], zonas) do
    zona = %Zona{
      codigo: codigo,
      nombre: nombre,
      nivel: Comun.atomo(nivel, Zona.niveles()),
      afectados: String.to_integer(afectados),
      sectores: []
    }

    Map.put(zonas, codigo, zona)
  end

  defp agregar_registro(["SECTOR", codigo_zona, codigo, nombre, nivel, afectados], zonas) do
    sector = %Sector{
      codigo: codigo,
      nombre: nombre,
      nivel: Comun.atomo(nivel, Zona.niveles()),
      afectados: String.to_integer(afectados),
      puntos: []
    }

    Map.update!(zonas, codigo_zona, fn z -> %{z | sectores: z.sectores ++ [sector]} end)
  end

  defp agregar_registro(["PUNTO", codigo_zona, codigo_sector, codigo, nombre, afectados], zonas) do
    punto = %PuntoAtencion{codigo: codigo, nombre: nombre, afectados: String.to_integer(afectados)}

    Map.update!(zonas, codigo_zona, fn z ->
      sectores =
        Enum.map(z.sectores, fn s ->
          if s.codigo == codigo_sector, do: %{s | puntos: s.puntos ++ [punto]}, else: s
        end)

      %{z | sectores: sectores}
    end)
  end

  defp agregar_registro(_registro_desconocido, zonas), do: zonas
end
