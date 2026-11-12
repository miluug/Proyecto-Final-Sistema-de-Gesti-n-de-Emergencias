defmodule Emergencias.UsuariosPersistenciaTest do
  use ExUnit.Case, async: false

  alias Emergencias.{Bitacora, Cliente, Inventario, Usuarios}
  import Emergencias.Ayuda

  setup do
    Emergencias.reiniciar()
    :ok
  end

  test "registro automático, validación de contraseña y desconexión" do
    assert {:ok, pid, usuario, _} = Cliente.conectar("ana", "clave1", "ciudadano", "centro", "Ana Ruiz")
    assert usuario.nombre == "Ana Ruiz"
    # ya tiene una sesión activa
    assert {:error, _} = Cliente.conectar("ana", "clave1")
    Cliente.desconectar(pid, usuario)

    assert {:error, _} = Cliente.conectar("ana", "otra_clave")
    assert {:ok, _pid, _usuario, mensaje} = Cliente.conectar("ana", "clave1")
    assert mensaje =~ "Bienvenido"

    # usuario nuevo sin tipo ni zona
    assert {:error, _} = Cliente.conectar("nuevo", "123")
  end

  test "las operaciones se restringen según el tipo de usuario" do
    ciudadano = conectar("carlos", "ciudadano", "centro")
    assert {:error, mensaje} = Cliente.ejecutar(ciudadano, "register_resource R1 agua 5 litros c1")
    assert mensaje =~ "no puede ejecutar"
    assert {:error, _} = Cliente.ejecutar(ciudadano, "summary")
    assert {:ok, _} = Cliente.ejecutar(ciudadano, "help")
  end

  test "se registra la actividad de cada usuario (proceso Bitácora)" do
    pid = conectar("maria", "administrador", "centro")
    Cliente.ejecutar(pid, "whoami")
    registros = Bitacora.consultar("maria")
    assert Enum.any?(registros, &(&1 =~ "whoami"))
  end

  test "si un GenServer falla, el supervisor lo reinicia y recupera los datos del archivo" do
    coordinador = conectar("laura", "coordinador", "centro")
    Cliente.ejecutar(coordinador, ~s(register_zone centro "Centro" alto))
    {:ok, _} = Cliente.ejecutar(coordinador, "register_resource R001 agua 50 litros centro_acopio_1")

    anterior = Process.whereis(Inventario)
    Process.exit(anterior, :kill)
    esperar_reinicio(Inventario, anterior)

    assert {:ok, recurso} = Inventario.obtener("R001")
    assert recurso.cantidad == 50
    assert File.exists?(Emergencias.Persistencia.ruta("recursos.txt"))
  end

  test "si la sesión de un usuario termina, queda desconectado" do
    pid = conectar("pepe", "voluntario", "centro")
    assert MapSet.member?(Usuarios.conectados(), "pepe")
    Process.exit(pid, :kill)
    :timer.sleep(50)
    refute MapSet.member?(Usuarios.conectados(), "pepe")
  end
  
end
