defmodule Emergencias.RecursividadTest do
  use ExUnit.Case, async: false

  # Las reglas del dominio son funciones puras: se prueban sin procesos ni archivos

  alias Emergencias.Comandos
  alias Emergencias.Dominio.{Mascota, Necesidad, PuntoAtencion, Recurso, Sector, Zona}

  # Zona centro -> 2 sectores -> 3 puntos de atención
  defp zona_ejemplo do
    %Zona{
      codigo: "centro",
      nombre: "Centro",
      nivel: :critico,
      afectados: 100,
      sectores: [
        %Sector{
          codigo: "S1",
          nombre: "Sector 1",
          nivel: :critico,
          afectados: 50,
          puntos: [
            %PuntoAtencion{codigo: "P1", nombre: "Parque", afectados: 20},
            %PuntoAtencion{codigo: "P2", nombre: "Colegio", afectados: 30}
          ]
        },
        %Sector{
          codigo: "S2",
          nombre: "Sector 2",
          nivel: :medio,
          afectados: 10,
          puntos: [%PuntoAtencion{codigo: "P3", nombre: "Iglesia", afectados: 5}]
        }
      ]
    }
  end

  test "1. tokenizar respeta las comillas" do
    assert Comandos.tokenizar(~s(register_need agua 30 critica centro "Punto de atención sector 3")) ==
             ["register_need", "agua", "30", "critica", "centro", "Punto de atención sector 3"]

    assert Comandos.tokenizar(~s(register_resource R1 agua 5 litros c1 nombre="Agua potable")) ==
             ["register_resource", "R1", "agua", "5", "litros", "c1", "nombre=Agua potable"]

    assert Comandos.tokenizar("   ") == []
  end

  test "2. total_afectados recorre zona -> sectores -> puntos" do
    # 100 + (50 + 20 + 30) + (10 + 5)
    assert Zona.total_afectados(zona_ejemplo()) == 215
    assert Zona.total_afectados([zona_ejemplo(), zona_ejemplo()]) == 430
  end

  test "3. contar_puntos y arbol" do
    assert Zona.contar_puntos(zona_ejemplo()) == 3
    lineas = Zona.arbol(zona_ejemplo())
    assert length(lineas) == 6
    assert String.starts_with?(Enum.at(lineas, 2), "        Punto P1")
  end

  test "4. repartir y total_disponible en el inventario" do
    recursos = [%Recurso{codigo: "R1", cantidad: 20}, %Recurso{codigo: "R2", cantidad: 30}]
    assert Recurso.total_disponible(recursos) == 50
    assert Recurso.repartir(recursos, 35, []) == [{"R1", 20}, {"R2", 15}]
    assert Recurso.repartir(recursos, 10, []) == [{"R1", 10}]
  end

  test "5. mas_urgente selecciona por prioridad y luego por antigüedad" do
    lista = [
      %Necesidad{id: "N001", prioridad: :media},
      %Necesidad{id: "N002", prioridad: :critica},
      %Necesidad{id: "N003", prioridad: :critica}
    ]

    assert Necesidad.mas_urgente(lista).id == "N002"
    assert Necesidad.mas_urgente([]) == nil
  end

  test "6. coincidencias de mascotas con puntaje" do
    perdida = %Mascota{id: "MAS001", tipo: :perdida, especie: "perro", color: "negra", tamano: :mediana, zona: "norte", caracteristicas: "collar rojo"}
    encontrada = %Mascota{id: "MAS002", tipo: :encontrada, especie: "perro", color: "negra", tamano: :mediana, zona: "norte", caracteristicas: "collar rojo"}
    gato = %Mascota{id: "MAS003", tipo: :encontrada, especie: "gato", color: "negra", tamano: :mediana, zona: "norte"}

    assert Mascota.puntaje(perdida, encontrada) == 100
    assert Mascota.puntaje(perdida, gato) == 0
    assert [{^perdida, ^encontrada, 100}] = Mascota.coincidencias([perdida], [encontrada, gato], [])
  end
end
