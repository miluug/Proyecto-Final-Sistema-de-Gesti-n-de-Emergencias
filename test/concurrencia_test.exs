defmodule Emergencias.ConcurrenciaTest do
  @moduledoc """
  Pruebas del conflicto concurrente: varias solicitudes simultáneas
  (Task.async, visto en clase) sobre el mismo recurso o albergue.
  """
  use ExUnit.Case, async: false

  alias Emergencias.{Albergues, Cliente, Inventario}
  import Emergencias.Ayuda

  setup do
    Emergencias.reiniciar()
    laura = conectar("laura", "coordinador", "centro")
    Cliente.ejecutar(laura, ~s(register_zone centro "Zona Centro" critico afectados=500))
    %{laura: laura}
  end

  test "flujo del enunciado: 30 + 25 litros sobre 50 disponibles", %{laura: laura} do
    pedro = conectar("pedro", "coordinador", "centro")

    ejecutar_todos(laura, [
      ~s(register_need agua 30 critica centro "Punto de atención sector 3"),
      ~s(register_need agua 25 alta centro "Albergue temporal"),
      "register_resource R001 agua 50 litros centro_acopio_1"
    ])

    # Las dos asignaciones se lanzan AL MISMO TIEMPO desde dos sesiones distintas
    tareas = [
      Task.async(fn -> Cliente.ejecutar(laura, "assign_resource N001 agua 30") end),
      Task.async(fn -> Cliente.ejecutar(pedro, "assign_resource N002 agua 25") end)
    ]

    resultados = Enum.map(tareas, &Task.await(&1, 10_000))

    # Solo una puede confirmarse: nunca se asignan 55 litros cuando hay 50
    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
    assert Enum.count(resultados, &match?({:error, _}, &1)) == 1

    {:ok, recurso} = Inventario.obtener("R001")
    assert recurso.cantidad in [20, 25]
    assert recurso.cantidad >= 0
  end

  test "50 solicitudes simultáneas de 5 unidades sobre 100 disponibles", %{laura: laura} do
    Cliente.ejecutar(laura, "register_resource R001 agua 100 litros centro_acopio_1")

    ids =
      for _numero <- 1..50 do
        {:ok, texto} = Cliente.ejecutar(laura, ~s(register_need agua 5 media centro "familia"))
        [_, id] = Regex.run(~r/(N\d+)/, texto)
        id
      end

    resultados =
      ids
      |> Enum.map(fn id -> Task.async(fn -> Emergencias.Necesidades.asignar_recurso(id, :agua, 5, "laura") end) end)
      |> Enum.map(&Task.await(&1, 10_000))

    exitosas = Enum.count(resultados, &match?({:ok, _necesidad, _tomados}, &1))
    {:ok, recurso} = Inventario.obtener("R001")

    assert exitosas == 20
    assert recurso.cantidad == 0
  end

  test "la misma necesidad no consume recursos dos veces aunque se pida a la vez", %{laura: laura} do
    ejecutar_todos(laura, [
      ~s(register_need agua 10 critica centro "punto 1"),
      "register_resource R001 agua 100 litros centro_acopio_1"
    ])

    resultados =
      1..5
      |> Enum.map(fn _ -> Task.async(fn -> Cliente.ejecutar(laura, "assign_resource N001 agua 10") end) end)
      |> Enum.map(&Task.await(&1, 10_000))

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 1
    {:ok, recurso} = Inventario.obtener("R001")
    assert recurso.cantidad == 90
  end

  test "ingresos simultáneos no superan la capacidad del albergue", %{laura: laura} do
    Cliente.ejecutar(laura, ~s(register_shelter A01 "Albergue Norte" centro 10))

    resultados =
      1..30
      |> Enum.map(fn n -> Task.async(fn -> Albergues.ingreso("A01", "DOC#{n}") end) end)
      |> Enum.map(&Task.await(&1, 10_000))

    assert Enum.count(resultados, &match?({:ok, _}, &1)) == 10
    {:ok, albergue} = Albergues.obtener("A01")
    assert Emergencias.Dominio.Albergue.ocupacion(albergue) == 10
  end
end
