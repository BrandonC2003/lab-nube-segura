data "azuread_domains" "inicial" {
  only_initial = true
}

data "azurerm_subscription" "actual" {}

locals {
  dominio_entra = data.azuread_domains.inicial.domains[0].domain_name

  usuarios = {
    finanzas01  = { nombre = "Usuario Finanzas 01", grupo = "finanzas" }
    operativo01 = { nombre = "Usuario Operativo 01", grupo = "operativo" }
    comercial01 = { nombre = "Usuario Comercial Remoto 01", grupo = "comercial-remoto" }
    comercial02 = { nombre = "Usuario Comercial Remoto 02", grupo = "comercial-remoto" }
    adminti01   = { nombre = "Administrador TI 01", grupo = "admins-ti" }
    adminti02   = { nombre = "Administrador TI 02", grupo = "admins-ti" }
  }

  cuentas_emergencia = toset(["emergencia01", "emergencia02"])

  grupos_entra = {
    finanzas         = { descripcion = "Personal de finanzas", asignable_a_roles = false }
    operativo        = { descripcion = "Personal operativo", asignable_a_roles = false }
    comercial-remoto = { descripcion = "Personal comercial con acceso remoto al ERP", asignable_a_roles = false }
    admins-ti        = { descripcion = "Administradores de TI (roles privilegiados solo por PIM)", asignable_a_roles = true }
    sql-admins       = { descripcion = "Administradores de Entra ID del servidor Azure SQL", asignable_a_roles = false }
    break-glass      = { descripcion = "Cuentas de emergencia excluidas de las políticas de bloqueo", asignable_a_roles = false }
  }

  miembros_grupo = {
    for g in keys(local.grupos_entra) : g => concat(
      [for clave, u in local.usuarios : azuread_user.usuario[clave].object_id if u.grupo == g],
      g == "sql-admins" ? var.administradores_lab : [],
      g == "break-glass" ? [for c in local.cuentas_emergencia : azuread_user.emergencia[c].object_id] : []
    )
  }
}

# ================= USUARIOS DE PRUEBA =================
resource "random_password" "usuario" {
  for_each = local.usuarios

  length           = 20
  override_special = "!#%*-_=+"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "azuread_user" "usuario" {
  for_each = local.usuarios

  user_principal_name   = "${each.key}@${local.dominio_entra}"
  display_name          = each.value.nombre
  mail_nickname         = each.key
  password              = random_password.usuario[each.key].result
  force_password_change = true
  usage_location        = "SV"
}

resource "azurerm_key_vault_secret" "usuario" {
  for_each = local.usuarios

  name         = "entra-${each.key}"
  value        = random_password.usuario[each.key].result
  key_vault_id = azurerm_key_vault.principal.id
  content_type = "contrasena-inicial-entra-id"

  depends_on = [azurerm_role_assignment.kv_equipo]
}

# ================= CUENTAS DE EMERGENCIA =================
# Solo en la nube, Global Administrator permanente y excluidas de CA01 y CA04.
# Su inicio de sesión genera una alerta en Sentinel.
resource "random_password" "emergencia" {
  for_each = local.cuentas_emergencia

  length           = 32
  override_special = "!#%*-_=+"
  min_lower        = 4
  min_upper        = 4
  min_numeric      = 4
  min_special      = 4
}

resource "azuread_user" "emergencia" {
  for_each = local.cuentas_emergencia

  user_principal_name = "${each.key}@${local.dominio_entra}"
  display_name        = "Cuenta de emergencia ${trimprefix(each.key, "emergencia")}"
  mail_nickname       = each.key
  password            = random_password.emergencia[each.key].result
  usage_location      = "SV"
}

resource "azurerm_key_vault_secret" "emergencia" {
  for_each = local.cuentas_emergencia

  name         = "entra-${each.key}"
  value        = random_password.emergencia[each.key].result
  key_vault_id = azurerm_key_vault.principal.id
  content_type = "contrasena-cuenta-emergencia"

  depends_on = [azurerm_role_assignment.kv_equipo]
}

resource "azuread_directory_role" "global_admin" {
  display_name = "Global Administrator"
}

resource "azuread_directory_role_assignment" "emergencia" {
  for_each = local.cuentas_emergencia

  role_id             = azuread_directory_role.global_admin.template_id
  principal_object_id = azuread_user.emergencia[each.key].object_id
}

# ================= GRUPOS =================
resource "azuread_group" "grupo" {
  for_each = local.grupos_entra

  display_name       = "grp-${each.key}"
  description        = each.value.descripcion
  security_enabled   = true
  assignable_to_role = each.value.asignable_a_roles
  members            = local.miembros_grupo[each.key]
}

# ================= ACCESO CONDICIONAL =================
resource "azuread_named_location" "el_salvador" {
  display_name = "El Salvador"

  country {
    countries_and_regions                 = ["SV"]
    include_unknown_countries_and_regions = false
  }
}

locals {
  grupo_emergencia = azuread_group.grupo["break-glass"].object_id

  # Fortaleza de autenticación integrada "Phishing-resistant MFA"
  fortaleza_resistente_phishing = "/policies/authenticationStrengthPolicies/00000000-0000-0000-0000-000000000004"

  # Windows Azure Service Management API (portal, CLI, PowerShell, Terraform)
  app_administracion_azure = "797f4846-ba00-4fd7-ba43-dac1f8f63013"
}

resource "azuread_conditional_access_policy" "ca01_mfa_todos" {
  display_name = "CA01 - MFA para todos los usuarios"
  state        = var.estado_acceso_condicional

  conditions {
    client_app_types = ["all"]

    applications {
      included_applications = ["All"]
    }

    users {
      included_users  = ["All"]
      excluded_groups = [local.grupo_emergencia]
    }
  }

  grant_controls {
    operator          = "OR"
    built_in_controls = ["mfa"]
  }
}

resource "azuread_conditional_access_policy" "ca02_bloquear_heredada" {
  display_name = "CA02 - Bloquear autenticación heredada"
  state        = var.estado_acceso_condicional

  conditions {
    client_app_types = ["exchangeActiveSync", "other"]

    applications {
      included_applications = ["All"]
    }

    users {
      included_users = ["All"]
    }
  }

  grant_controls {
    operator          = "OR"
    built_in_controls = ["block"]
  }
}

resource "azuread_conditional_access_policy" "ca03_admins_resistente_phishing" {
  display_name = "CA03 - Administradores con MFA resistente a phishing"
  state        = var.estado_acceso_condicional

  conditions {
    client_app_types = ["all"]

    applications {
      included_applications = ["All"]
    }

    users {
      included_groups = [azuread_group.grupo["admins-ti"].object_id]
      excluded_groups = [local.grupo_emergencia]
    }
  }

  grant_controls {
    operator                          = "OR"
    authentication_strength_policy_id = local.fortaleza_resistente_phishing
  }
}

resource "azuread_conditional_access_policy" "ca04_solo_el_salvador" {
  display_name = "CA04 - Bloquear inicios de sesión fuera de El Salvador"
  state        = var.estado_acceso_condicional

  conditions {
    client_app_types = ["all"]

    applications {
      included_applications = ["All"]
    }

    users {
      included_users  = ["All"]
      excluded_groups = [local.grupo_emergencia]
    }

    locations {
      included_locations = ["All"]
      excluded_locations = [azuread_named_location.el_salvador.id]
    }
  }

  grant_controls {
    operator          = "OR"
    built_in_controls = ["block"]
  }
}

resource "azuread_conditional_access_policy" "ca05_mfa_administracion_azure" {
  display_name = "CA05 - MFA para la administración de Azure"
  state        = var.estado_acceso_condicional

  conditions {
    client_app_types = ["all"]

    applications {
      included_applications = [local.app_administracion_azure]
    }

    users {
      included_users  = ["All"]
      excluded_groups = [local.grupo_emergencia]
    }
  }

  grant_controls {
    operator          = "OR"
    built_in_controls = ["mfa"]
  }
}

# Condición de dispositivo para el acceso remoto (prueba V3): solo plataformas aprobadas
resource "azuread_conditional_access_policy" "ca06_plataformas_aprobadas" {
  display_name = "CA06 - Comercial remoto solo desde plataformas aprobadas"
  state        = var.estado_acceso_condicional

  conditions {
    client_app_types = ["all"]

    applications {
      included_applications = ["All"]
    }

    users {
      included_groups = [azuread_group.grupo["comercial-remoto"].object_id]
    }

    platforms {
      included_platforms = ["all"]
      excluded_platforms = ["windows", "macOS", "iOS", "android"]
    }
  }

  grant_controls {
    operator          = "OR"
    built_in_controls = ["block"]
  }
}

# ================= PIM: ROLES DE ENTRA ID =================
resource "azuread_directory_role" "user_admin" {
  display_name = "User Administrator"
}

resource "azuread_directory_role_eligibility_schedule_request" "admins_ti_user_admin" {
  role_definition_id = azuread_directory_role.user_admin.template_id
  principal_id       = azuread_group.grupo["admins-ti"].object_id
  directory_scope_id = "/"
  justification      = "Elegibilidad de administradores de TI; activación bajo demanda"
}

# ================= PIM: ROLES DE AZURE (prueba V5) =================
data "azurerm_role_definition" "contributor_suscripcion" {
  name  = "Contributor"
  scope = data.azurerm_subscription.actual.id
}

data "azurerm_role_definition" "contributor_core" {
  name  = "Contributor"
  scope = azurerm_resource_group.rg["core"].id
}

resource "azurerm_pim_eligible_role_assignment" "admins_ti_contributor" {
  scope              = azurerm_resource_group.rg["core"].id
  role_definition_id = data.azurerm_role_definition.contributor_suscripcion.id
  principal_id       = azuread_group.grupo["admins-ti"].object_id
  justification      = "Administración de la capa persistente bajo demanda"

  schedule {
    expiration {
      duration_days = 90
    }
  }

  depends_on = [azurerm_role_management_policy.contributor_core]
}

# Activación de máximo 4 h, con justificación y aprobación
resource "azurerm_role_management_policy" "contributor_core" {
  scope              = azurerm_resource_group.rg["core"].id
  role_definition_id = data.azurerm_role_definition.contributor_core.id

  activation_rules {
    maximum_duration      = "PT4H"
    require_justification = true
    require_approval      = true

    approval_stage {
      primary_approver {
        object_id = var.administradores_lab[0]
        type      = "User"
      }
    }
  }
}

# ================= CONTROLADOR DE DOMINIO (sede) =================
resource "random_password" "dsrm" {
  length           = 24
  override_special = "!#%*-_=+"
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

module "vm_dc01" {
  source = "./modules/vm_windows"

  nombre           = "vm-dc01"
  grupo_recursos   = local.rg_sede
  ubicacion        = var.ubicacion_sede
  tamano           = var.tamano_vm_windows
  hora_apagado     = var.hora_apagado_vms
  subnet_id        = module.vnet_sede.subredes["vlan-identidad"]
  ip_privada       = "192.168.40.10"
  script_inicio    = file("${path.module}/scripts/dc-inicio.ps1")
  variables_script = { ContrasenaDsrm = random_password.dsrm.result }
  etiquetas        = var.etiquetas
}

resource "azurerm_key_vault_secret" "dc01_admin" {
  name         = "vm-dc01-azureadmin"
  value        = module.vm_dc01.contrasena_admin
  key_vault_id = azurerm_key_vault.principal.id
  content_type = "contrasena-administrador-dominio"

  depends_on = [azurerm_role_assignment.kv_equipo]
}

resource "azurerm_key_vault_secret" "dc01_dsrm" {
  name         = "vm-dc01-dsrm"
  value        = random_password.dsrm.result
  key_vault_id = azurerm_key_vault.principal.id
  content_type = "contrasena-dsrm"

  depends_on = [azurerm_role_assignment.kv_equipo]
}
