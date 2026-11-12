# =====================================================================
#  Demostración del flujo de ejemplo del enunciado y del conflicto
#  concurrente resuelto.
#
#  Ejecutar desde la carpeta del proyecto:
#      mix run scripts/demo_concurrencia.exs
#
#  Usa la carpeta datos_demo para no mezclar con los datos reales.
# =====================================================================

alias Emergencias.{Cliente, Inventario}

# Se reinicia la aplicación apuntando a la carpeta de la demostración
Application.stop(:emergencias)
File.rm_rf!("datos_demo")
Application.put_env(:emergencias, :directorio_datos, "datos_demo")
{:ok, _} = Application.ensure_all_started(:emergencias)

defmodule Demo do
  def titulo(texto), do: Util2.mostrar("\n========== #{texto} ==========", :mensaje)

  # Ejecuta un comando en la sesión del usuario y muestra el resultado
  def ejecutar({pid, usuario}, linea) do
    Util2.mostrar("\n[#{usuario.usuario} - #{usuario.tipo}]> #{linea}", :mensaje)

    case Cliente.ejecutar(pid, linea) do
      {:ok, texto} -> Util2.mostrar(texto, :mensaje)
      {:error, texto} -> Util2.mostrar("ERROR: " <> texto, :mensaje)
    end
  end

  def conectar(usuario, clave, tipo, zona, nombre) do
    {:ok, pid, datos, mensaje} = Cliente.conectar(usuario, clave, tipo, zona, nombre)
    Util2.mostrar("connect #{usuario} -> #{mensaje}", :mensaje)
    {pid, datos}
  end
end

Demo.titulo("1. Conexión de usuarios (cada uno con su propio proceso de sesión)")
laura = Demo.conectar("laura", "1234", "coordinador", "centro", "Laura Gómez")
pedro = Demo.conectar("pedro", "abcd", "coordinador", "centro", "Pedro Ríos")
ciudadano = Demo.conectar("andrea", "1111", "ciudadano", "zona_norte", "Andrea Mora")
voluntario = Demo.conectar("samuel", "2222", "voluntario", "zona_norte", "Samuel Paz")

Demo.titulo("2. Zonas, necesidades y recursos")
Demo.ejecutar(laura, ~s(register_zone centro "Zona Centro" critico afectados=800))
Demo.ejecutar(laura, ~s(register_zone zona_norte "Zona Norte" alto afectados=300))
Demo.ejecutar(laura, ~s(register_sector centro S3 "Sector 3" critico 120))
Demo.ejecutar(laura, ~s(register_point centro S3 PA1 "Polideportivo" 60))
Demo.ejecutar(laura, ~s(register_need agua 30 critica centro "Punto de atención sector 3"))
Demo.ejecutar(pedro, ~s(register_need agua 25 alta centro "Familias del sector 3"))
Demo.ejecutar(laura, "register_resource R001 agua 50 litros centro_acopio_1")

Demo.titulo("3. CONFLICTO CONCURRENTE: dos asignaciones al mismo tiempo (30 + 25 sobre 50)")

tareas = [
  Task.async(fn -> {"laura", Cliente.ejecutar(elem(laura, 0), "assign_resource N001 agua 30")} end),
  Task.async(fn -> {"pedro", Cliente.ejecutar(elem(pedro, 0), "assign_resource N002 agua 25")} end)
]

tareas
|> Enum.map(&Task.await(&1, 10_000))
|> Enum.each(fn {quien, resultado} -> Util2.mostrar("  #{quien}: #{inspect(resultado)}", :mensaje) end)

{:ok, recurso} = Inventario.obtener("R001")
Util2.mostrar("  -> Quedan #{recurso.cantidad} litros. Nunca se asignaron 55 litros.", :mensaje)

Demo.titulo("4. Prueba de carga: 40 solicitudes simultáneas de 5 litros sobre 100")
Demo.ejecutar(laura, "register_resource R002 agua 100 litros centro_acopio_2")

ids =
  for _ <- 1..40 do
    {:ok, texto} = Cliente.ejecutar(elem(laura, 0), ~s(register_need agua 5 media centro "kit familiar"))
    [_, id] = Regex.run(~r/(N\d+)/, texto)
    id
  end

{tiempo, resultados} =
  :timer.tc(fn ->
    ids
    |> Enum.map(fn id -> Task.async(fn -> Cliente.ejecutar(elem(pedro, 0), "assign_resource #{id} agua 5") end) end)
    |> Enum.map(&Task.await(&1, 20_000))
  end)

exitosas = Enum.count(resultados, &match?({:ok, _}, &1))
{:ok, r2} = Inventario.obtener("R002")
{:ok, r1} = Inventario.obtener("R001")

Util2.mostrar(
  "  Confirmadas: #{exitosas} | rechazadas: #{40 - exitosas} | quedan R001=#{r1.cantidad} R002=#{r2.cantidad} | #{tiempo} microsegundos",
  :mensaje
)

Demo.titulo("5. Comunicación entre familiares")
Demo.ejecutar(laura, ~s(register_shelter A01 "Albergue Norte" zona_norte 150))
Demo.ejecutar(ciudadano, ~s(report_person 1094 "Andrés López" zona_norte localizada edad=34))
Demo.ejecutar(voluntario, "register_entry A01 1094")
Demo.ejecutar(ciudadano, ~s(send_family_message 1094 "Andrés, somos tu familia, vamos para el albergue"))
Demo.ejecutar(ciudadano, "list_family_messages 1094")

Demo.titulo("6. Mascotas perdidas y encontradas")
Demo.ejecutar(ciudadano, ~s(report_pet lost perro "Luna" negra mediana zona_norte 3001234567 caracteristicas="collar rojo"))
Demo.ejecutar(voluntario, ~s(report_pet found perro desconocido negra mediana zona_norte 3157654321 caracteristicas="collar rojo"))
Demo.ejecutar(voluntario, "match_pets")

Demo.titulo("7. Resumen global del coordinador")
Demo.ejecutar(laura, "summary")
Demo.ejecutar(laura, "critical_resources")
Demo.ejecutar(laura, "zone_status centro")

Enum.each([laura, pedro, ciudadano, voluntario], fn {pid, usuario} -> Cliente.desconectar(pid, usuario) end)

Util2.mostrar("\nDemostración terminada. Los archivos quedaron en la carpeta datos_demo/", :mensaje)
