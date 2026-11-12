defmodule Emergencias.DominioTest do
  @moduledoc "Validaciones y reglas de negocio a través de los comandos."
  use ExUnit.Case, async: false

  alias Emergencias.Cliente
  import Emergencias.Ayuda

  setup do
    Emergencias.reiniciar()
    coordinadora = conectar("laura", "coordinador", "centro")

    ejecutar_todos(coordinadora, [
      ~s(register_zone centro "Zona Centro" critico afectados=100),
      ~s(register_zone zona_norte "Zona Norte" alto)
    ])

    %{c: coordinadora}
  end

  defp ok?(resultado), do: match?({:ok, _}, resultado)

  test "zonas, sectores, puntos y estado de zona", %{c: c} do
    assert ok?(Cliente.ejecutar(c, ~s(register_sector centro S1 "Sector 1" critico 40)))
    assert ok?(Cliente.ejecutar(c, ~s(register_point centro S1 P1 "Parque" 15)))
    assert {:error, _} = Cliente.ejecutar(c, ~s(register_zone centro "Repetida" alto))
    assert {:error, _} = Cliente.ejecutar(c, ~s(register_zone sur "Sur" muy_alto))
    assert {:error, _} = Cliente.ejecutar(c, ~s(register_sector centro S2 "Sector 2" medio -5))

    {:ok, texto} = Cliente.ejecutar(c, "zone_status centro")
    assert texto =~ "afectados 155"
  end

  test "necesidades: prioridad, estados y cierre", %{c: c} do
    ejecutar_todos(c, [
      ~s(register_need agua 10 baja centro "uno"),
      ~s(register_need alimentos 5 critica centro "dos"),
      "register_resource R001 agua 50 litros bodega_1"
    ])

    {:ok, siguiente} = Cliente.ejecutar(c, "next_need")
    assert siguiente =~ "N002"

    {:ok, lista} = Cliente.ejecutar(c, "list_needs zona=centro")
    assert :binary.match(lista, "N002") < :binary.match(lista, "N001")

    assert {:error, _} = Cliente.ejecutar(c, "register_need agua -3 alta centro x")
    assert {:error, _} = Cliente.ejecutar(c, "register_need agua 3 alta zona_fantasma x")
    assert {:error, _} = Cliente.ejecutar(c, "assign_resource N001 agua 11")

    assert ok?(Cliente.ejecutar(c, "assign_resource N001 agua 10"))
    assert ok?(Cliente.ejecutar(c, "update_need N001 atendida"))
    # no se puede cerrar dos veces ni volver a consumir recursos
    assert {:error, _} = Cliente.ejecutar(c, "update_need N001 atendida")
    assert {:error, _} = Cliente.ejecutar(c, "assign_resource N001 agua 1")
    # transición inválida: pendiente -> atendida
    assert {:error, _} = Cliente.ejecutar(c, "update_need N002 atendida")
  end

  test "recursos: entradas, salidas, transferencias e historial", %{c: c} do
    assert ok?(Cliente.ejecutar(c, "register_resource R001 agua 200 litros centro_acopio_1"))
    assert {:error, _} = Cliente.ejecutar(c, "register_resource R001 agua 5 litros otro")
    assert {:error, _} = Cliente.ejecutar(c, "register_resource R009 agua -5 litros otro")
    assert ok?(Cliente.ejecutar(c, "resource_in R001 20"))
    assert {:error, _} = Cliente.ejecutar(c, "resource_out R001 500")
    assert ok?(Cliente.ejecutar(c, "transfer_resource R001 centro_acopio_1 albergue_2 30"))

    {:ok, origen} = Emergencias.Inventario.obtener("R001")
    {:ok, destino} = Emergencias.Inventario.obtener("R001-albergue_2")
    assert origen.cantidad == 190
    assert destino.cantidad == 30
    assert length(Emergencias.Inventario.historial("R001")) == 3
  end

  test "familiares: personas, estados e historial, mensajes", %{c: c} do
    assert ok?(Cliente.ejecutar(c, ~s(report_person 1094 "Andrés López" centro localizada edad=34)))
    assert {:error, _} = Cliente.ejecutar(c, ~s(report_person 1094 "Otro" centro reportada))
    assert {:error, _} = Cliente.ejecutar(c, "update_person 1094 sin_informacion")
    assert ok?(Cliente.ejecutar(c, "update_person 1094 en_albergue"))

    {:ok, encontrados} = Cliente.ejecutar(c, "find_person nombre=andrés")
    assert encontrados =~ "1094"

    assert ok?(Cliente.ejecutar(c, ~s(send_family_message 1094 "Estoy bien, estoy en el albergue norte")))
    assert {:error, _} = Cliente.ejecutar(c, ~s(send_family_message 0000 "hola"))
    assert ok?(Cliente.ejecutar(c, "mark_message M001 entregado"))

    {:ok, persona} = Emergencias.Familias.obtener("1094")
    assert length(persona.historial) == 2
  end

  test "mascotas: coincidencia y cierre de ambos reportes", %{c: c} do
    ejecutar_todos(c, [
      ~s(report_pet lost perro "Luna" negra mediana zona_norte 3001234567),
      ~s(report_pet found perro desconocido negra mediana zona_norte 3157654321)
    ])

    {:ok, texto} = Cliente.ejecutar(c, "match_pets")
    assert texto =~ "MAS001"
    assert ok?(Cliente.ejecutar(c, "confirm_match MAS001 MAS002"))
    assert {:error, _} = Cliente.ejecutar(c, "confirm_match MAS001 MAS002")
  end

  test "albergues: capacidad y duplicados", %{c: c} do
    assert ok?(Cliente.ejecutar(c, ~s(register_shelter A01 "Albergue Norte" zona_norte 2)))
    assert {:error, _} = Cliente.ejecutar(c, ~s(register_shelter A02 "Malo" zona_norte -1))
    assert ok?(Cliente.ejecutar(c, "register_entry A01 111"))
    assert {:error, _} = Cliente.ejecutar(c, "register_entry A01 111")
    assert ok?(Cliente.ejecutar(c, "register_entry A01 222"))
    assert {:error, _} = Cliente.ejecutar(c, "register_entry A01 333")
    assert ok?(Cliente.ejecutar(c, "register_exit A01 111"))
    assert ok?(Cliente.ejecutar(c, "register_entry A01 333"))
  end

  test "summary y recursos críticos", %{c: c} do
    ejecutar_todos(c, [
      ~s(register_need agua 80 critica centro "punto"),
      "register_resource R001 agua 50 litros centro_acopio_1"
    ])

    {:ok, criticos} = Cliente.ejecutar(c, "critical_resources")
    assert criticos =~ "agua en zona centro: disponible 50, demanda pendiente 80"
    assert ok?(Cliente.ejecutar(c, "summary"))
  end
end
