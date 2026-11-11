defmodule Emergencias.Permisos do
  @moduledoc """
  INTERFAZ (el CÓMO): catálogo de comandos: rol mínimo necesario y forma de uso.

  Jerarquía de roles: ciudadano (1) < voluntario (2) < coordinador (3) < administrador (4).
  Un usuario puede ejecutar un comando si el peso de su rol es mayor o igual
  al del rol mínimo del comando.
  """

  @comandos %{
    # generales
    "help" => {:ciudadano, "help"},
    "whoami" => {:ciudadano, "whoami"},
    "summary" => {:coordinador, "summary"},
    "list_users" => {:administrador, "list_users"},
    "activity" => {:administrador, "activity [usuario]"},
    # zonas
    "register_zone" => {:coordinador, "register_zone codigo \"nombre\" nivel [afectados=N]"},
    "register_sector" => {:coordinador, "register_sector zona codigo \"nombre\" nivel afectados"},
    "register_point" => {:voluntario, "register_point zona sector codigo \"nombre\" afectados"},
    "list_zones" => {:ciudadano, "list_zones"},
    "zone_status" => {:ciudadano, "zone_status codigo"},
    # necesidades
    "register_need" => {:ciudadano, "register_need tipo cantidad prioridad zona \"descripcion\" [para=albergue|documento]"},
    "list_needs" => {:ciudadano, "list_needs [zona=x] [tipo=x] [prioridad=x] [estado=x]"},
    "pending_needs" => {:ciudadano, "pending_needs"},
    "next_need" => {:voluntario, "next_need"},
    "assign_resource" => {:coordinador, "assign_resource id_necesidad tipo cantidad"},
    "update_need" => {:voluntario, "update_need id_necesidad estado"},
    # recursos
    "register_resource" => {:coordinador, "register_resource codigo categoria cantidad unidad ubicacion [zona=x] [nombre=\"x\"]"},
    "list_resources" => {:ciudadano, "list_resources [categoria=x] [zona=x] [ubicacion=x]"},
    "resource_in" => {:voluntario, "resource_in codigo cantidad"},
    "resource_out" => {:voluntario, "resource_out codigo cantidad"},
    "transfer_resource" => {:coordinador, "transfer_resource codigo origen destino cantidad [zona=x]"},
    "resource_history" => {:coordinador, "resource_history codigo"},
    "critical_resources" => {:coordinador, "critical_resources"},
    # comunicación entre familiares
    "report_person" => {:ciudadano, "report_person documento \"nombre\" zona estado [edad=N]"},
    "update_person" => {:voluntario, "update_person documento estado"},
    "find_person" => {:ciudadano, "find_person documento | find_person [nombre=x] [zona=x] [estado=x]"},
    "person_history" => {:ciudadano, "person_history documento"},
    "send_family_message" => {:ciudadano, "send_family_message documento|familia:apellido \"mensaje\""},
    "list_family_messages" => {:ciudadano, "list_family_messages documento|familia:apellido"},
    "mark_message" => {:voluntario, "mark_message id_mensaje entregado|pendiente"},
    # mascotas
    "report_pet" => {:ciudadano, "report_pet lost|found especie \"nombre\" color tamano zona contacto [caracteristicas=\"x\"]"},
    "list_pets" => {:ciudadano, "list_pets [especie=x] [zona=x] [estado=x] [tipo=x]"},
    "match_pets" => {:voluntario, "match_pets"},
    "confirm_match" => {:coordinador, "confirm_match id_perdida id_encontrada"},
    # albergues
    "register_shelter" => {:coordinador, "register_shelter codigo \"nombre\" zona capacidad"},
    "check_shelter" => {:ciudadano, "check_shelter codigo"},
    "list_shelters" => {:ciudadano, "list_shelters"},
    "register_entry" => {:voluntario, "register_entry codigo_albergue documento"},
    "register_exit" => {:voluntario, "register_exit codigo_albergue documento"},
    "shelter_ranking" => {:coordinador, "shelter_ranking"}
  }

  def peso(:ciudadano), do: 1
  def peso(:voluntario), do: 2
  def peso(:coordinador), do: 3
  def peso(:administrador), do: 4

  def existe?(comando), do: Map.has_key?(@comandos, comando)

  def permitido?(rol, comando) do
    case Map.fetch(@comandos, comando) do
      {:ok, {rol_minimo, _uso}} -> peso(rol) >= peso(rol_minimo)
      :error -> false
    end
  end

  def rol_minimo(comando), do: @comandos |> Map.fetch!(comando) |> elem(0)
  def uso(comando), do: @comandos |> Map.fetch!(comando) |> elem(1)

  @doc "Comandos que puede usar un rol (para el comando help)."
  def disponibles(rol) do
    @comandos
    |> Map.keys()
    |> Enum.filter(&permitido?(rol, &1))
    |> Enum.sort()
    |> Enum.map(&uso/1)
  end
end
