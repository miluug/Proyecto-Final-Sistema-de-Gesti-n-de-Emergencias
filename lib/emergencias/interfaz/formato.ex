defmodule Emergencias.Formato do
  @moduledoc """
  INTERFAZ (el CÓMO): cómo se MUESTRA cada struct del dominio en la consola.
  Se implementa el protocolo String.Chars (como en el ejemplo Reserva visto
  en clase) y las listas se convierten a texto con Util2.
  El dominio no sabe cómo se imprime: si cambia la presentación, solo se
  modifica este archivo.
  """

  @doc "Convierte una lista en texto con viñetas usando Util2."
  def lista(_titulo, []), do: "No hay registros."

  def lista(titulo, elementos) do
    "#{titulo} (#{length(elementos)}):\n" <>
      (elementos |> Util2.convertir_coleccion_mensaje() |> Enum.join())
  end
end

defimpl String.Chars, for: Emergencias.Dominio.Usuario do
  def to_string(u), do: "#{u.usuario} (#{u.nombre}) - #{u.tipo} - zona #{u.zona}"
end

defimpl String.Chars, for: Emergencias.Dominio.Zona do
  def to_string(z), do: "#{z.codigo} - #{z.nombre} [#{z.nivel}] afectados: #{z.afectados}"
end

defimpl String.Chars, for: Emergencias.Dominio.Necesidad do
  def to_string(n) do
    "#{n.id} | #{n.tipo} #{n.cantidad} (asignado #{n.asignada}) | prioridad #{n.prioridad} | " <>
      "zona #{n.zona} | para #{n.asociado_a} | #{n.estado} | \"#{n.descripcion}\" | reporta #{n.responsable}"
  end
end

defimpl String.Chars, for: Emergencias.Dominio.Recurso do
  def to_string(r) do
    "#{r.codigo} | #{r.nombre} (#{r.categoria}) | #{r.cantidad} #{r.unidad} | #{r.ubicacion} | zona #{r.zona}"
  end
end

defimpl String.Chars, for: Emergencias.Dominio.Movimiento do
  def to_string(m), do: "#{m.fecha} | #{m.tipo} | #{m.codigo} | #{m.cantidad} | #{m.detalle} | #{m.usuario}"
end

defimpl String.Chars, for: Emergencias.Dominio.Persona do
  def to_string(p) do
    edad = if p.edad, do: "#{p.edad} años", else: "edad desconocida"
    "#{p.id} | doc #{p.documento} | #{p.nombre} | #{edad} | zona #{p.zona} | #{p.estado}"
  end
end

defimpl String.Chars, for: Emergencias.Dominio.Mensaje do
  def to_string(m), do: "#{m.id} | #{m.fecha} | de #{m.remitente} para #{m.destinatario} | \"#{m.contenido}\" | #{m.estado}"
end

defimpl String.Chars, for: Emergencias.Dominio.Mascota do
  def to_string(m) do
    extra = if m.coincidencia == "", do: "", else: " | coincide con #{m.coincidencia}"

    "#{m.id} | #{m.tipo} | #{m.especie} \"#{m.nombre}\" | #{m.color}, #{m.tamano} | " <>
      "#{m.caracteristicas} | zona #{m.zona} | contacto #{m.contacto} | #{m.estado}#{extra}"
  end
end

defimpl String.Chars, for: Emergencias.Dominio.Albergue do
  alias Emergencias.Dominio.Albergue

  def to_string(a) do
    porcentaje = :erlang.float_to_binary(Albergue.porcentaje(a) * 1.0, decimals: 1)

    "#{a.codigo} | #{a.nombre} | zona #{a.zona} | ocupación #{Albergue.ocupacion(a)}/#{a.capacidad} " <>
      "(#{porcentaje}%) | cupos #{Albergue.cupos(a)}"
  end
end
