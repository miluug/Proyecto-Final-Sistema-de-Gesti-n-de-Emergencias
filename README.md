# Sistema Distribuido de Coordinación y Gestión de Emergencias en Elixir

Proyecto final – Programación III – Universidad del Quindío
Contexto: atención y coordinación posterior a un terremoto.

## Integrantes
- Luisa Fernanda Hernandez Ramirez
- Isabella Hincapié Bocanegra
- Camila de los Ángeles González Restrepo

## Descripción
Sistema multiusuario que simula una plataforma distribuida para coordinar la atención de una emergencia:
usuarios, zonas afectadas, necesidades, recursos e inventario, comunicación entre familiares,
mascotas perdidas y encontradas, y albergues.

Usa procesos concurrentes, GenServer, Supervisor y DynamicSupervisor, funciones recursivas
y persistencia en archivos de texto plano.

## Requisitos
- Elixir 1.15 o superior
- Sin dependencias externas

## Cómo ejecutar
Desde la carpeta del proyecto:

    mix compile                              # compilar
    mix test                                 # pruebas
    mix run scripts/demo_concurrencia.exs    # demostración del conflicto concurrente
    mix run -e "Emergencias.CLI.main()"      # consola interactiva

## Ejemplo de uso

    connect laura 1234 coordinador centro "Laura Gómez"
    register_zone centro "Zona Centro" critico afectados=800
    register_need agua 30 critica centro "Punto de atención sector 3"
    register_resource R001 agua 50 litros centro_acopio_1
    assign_resource N001 agua 30
    summary
    disconnect
