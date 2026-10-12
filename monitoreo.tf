# ================= LOG ANALYTICS + MICROSOFT SENTINEL =================
resource "azurerm_log_analytics_workspace" "principal" {
  name                = "law-${var.prefijo}-${local.sufijo}"
  location            = var.ubicacion
  resource_group_name = local.rg_core
  sku                 = "PerGB2018"
  retention_in_days   = 90
  daily_quota_gb      = 5 # tope de ingesta para proteger el crédito
  tags                = var.etiquetas
}

resource "azurerm_sentinel_log_analytics_workspace_onboarding" "principal" {
  workspace_id = azurerm_log_analytics_workspace.principal.id
}

locals {
  workspace_id = azurerm_log_analytics_workspace.principal.id
  sentinel_id  = azurerm_sentinel_log_analytics_workspace_onboarding.principal.workspace_id
}

# Prueba V9: registros por fuente en las últimas 24 h
resource "azurerm_log_analytics_saved_search" "v9_fuentes" {
  name                       = "v9-fuentes-con-datos"
  log_analytics_workspace_id = local.workspace_id
  category                   = "Validacion"
  display_name               = "V9 - Fuentes con datos en las últimas 24 h"

  query = <<-KQL
    union withsource = Tabla isfuzzy = true
      SigninLogs, AuditLogs, AzureActivity, AzureDiagnostics, Syslog, SecurityEvent, Heartbeat,
      AZFWNetworkRule, AZFWApplicationRule, AZFWIdpsSignature, AGWAccessLogs, AGWFirewallLogs
    | where TimeGenerated > ago(24h)
    | extend Fuente = iff(Tabla == "AzureDiagnostics", strcat("AzureDiagnostics/", Category), Tabla)
    | summarize Registros = count(), Ultimo = max(TimeGenerated) by Fuente
    | order by Fuente asc
  KQL
}

# ================= FUENTES DE DATOS =================
# Entra ID: inicios de sesión y auditoría (requiere licencia P1/P2)
resource "azurerm_monitor_aad_diagnostic_setting" "entra" {
  name                       = "diag-entra-a-sentinel"
  log_analytics_workspace_id = local.workspace_id

  dynamic "enabled_log" {
    for_each = ["SignInLogs", "NonInteractiveUserSignInLogs", "ServicePrincipalSignInLogs", "AuditLogs"]
    content {
      category = enabled_log.value
    }
  }
}

# Registro de actividad de la suscripción
resource "azurerm_monitor_diagnostic_setting" "actividad" {
  name                       = "diag-actividad-a-sentinel"
  target_resource_id         = data.azurerm_subscription.actual.id
  log_analytics_workspace_id = local.workspace_id

  dynamic "enabled_log" {
    for_each = ["Administrative", "Security", "Policy", "Alert"]
    content {
      category = enabled_log.value
    }
  }
}

resource "azurerm_monitor_diagnostic_setting" "key_vault" {
  name                       = "diag-kv-a-sentinel"
  target_resource_id         = azurerm_key_vault.principal.id
  log_analytics_workspace_id = local.workspace_id

  enabled_log {
    category_group = "audit"
  }
}

# Auditoría de Azure SQL enviada a Log Analytics
resource "azurerm_mssql_server_extended_auditing_policy" "erp" {
  server_id              = azurerm_mssql_server.erp.id
  log_monitoring_enabled = true
}

resource "azurerm_monitor_diagnostic_setting" "sql" {
  name                       = "diag-sql-a-sentinel"
  target_resource_id         = "${azurerm_mssql_server.erp.id}/databases/master"
  log_analytics_workspace_id = local.workspace_id

  enabled_log {
    category = "SQLSecurityAuditEvents"
  }

  depends_on = [azurerm_mssql_server_extended_auditing_policy.erp]
}

# Perímetro: tablas dedicadas (AZFWIdpsSignature, AGWFirewallLogs, ...)
resource "azurerm_monitor_diagnostic_setting" "firewall" {
  count = var.perimetro_activo ? 1 : 0

  name                           = "diag-fw-a-sentinel"
  target_resource_id             = module.perimetro[0].firewall_id
  log_analytics_workspace_id     = local.workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }
}

resource "azurerm_monitor_diagnostic_setting" "appgw" {
  count = var.perimetro_activo ? 1 : 0

  name                           = "diag-appgw-a-sentinel"
  target_resource_id             = module.perimetro[0].appgw_id
  log_analytics_workspace_id     = local.workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }
}

# ================= AZURE MONITOR AGENT =================
resource "azurerm_monitor_data_collection_rule" "linux" {
  name                = "dcr-${var.prefijo}-linux-syslog"
  location            = var.ubicacion
  resource_group_name = local.rg_core
  kind                = "Linux"
  tags                = var.etiquetas

  destinations {
    log_analytics {
      name                  = "sentinel"
      workspace_resource_id = local.workspace_id
    }
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["sentinel"]
  }

  data_sources {
    syslog {
      name           = "syslog-seguridad"
      streams        = ["Microsoft-Syslog"]
      facility_names = ["auth", "authpriv", "daemon", "kern", "syslog"]
      log_levels     = ["Info", "Notice", "Warning", "Error", "Critical", "Alert", "Emergency"]
    }
  }

  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.principal]
}

resource "azurerm_monitor_data_collection_rule" "windows" {
  name                = "dcr-${var.prefijo}-windows-seguridad"
  location            = var.ubicacion
  resource_group_name = local.rg_core
  kind                = "Windows"
  tags                = var.etiquetas

  destinations {
    log_analytics {
      name                  = "sentinel"
      workspace_resource_id = local.workspace_id
    }
  }

  data_flow {
    streams      = ["Microsoft-SecurityEvent"]
    destinations = ["sentinel"]
  }

  data_sources {
    windows_event_log {
      name    = "eventos-seguridad"
      streams = ["Microsoft-SecurityEvent"]
      # Inicios de sesión, privilegios, gestión de cuentas y grupos, borrado del registro
      x_path_queries = [
        "Security!*[System[(EventID=4624 or EventID=4625 or EventID=4648 or EventID=4672 or EventID=4688 or EventID=4720 or EventID=4722 or EventID=4724 or EventID=4725 or EventID=4726 or EventID=4728 or EventID=4732 or EventID=4740 or EventID=4756 or EventID=1102)]]",
      ]
    }
  }

  depends_on = [azurerm_sentinel_log_analytics_workspace_onboarding.principal]
}

locals {
  vms_linux = {
    web01   = module.vm_web01.id
    jump01  = module.vm_jump01.id
    gw-sede = module.vm_router_sede.id
    admin01 = module.vm_sede["vm-admin01"].id
    srv01   = module.vm_sede["vm-srv01"].id
  }

  vms_windows = {
    erp01 = module.vm_erp01.id
    dc01  = module.vm_dc01.id
  }
}

resource "azurerm_virtual_machine_extension" "ama_linux" {
  for_each = local.vms_linux

  name                       = "AzureMonitorLinuxAgent"
  virtual_machine_id         = each.value
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorLinuxAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = var.etiquetas
}

resource "azurerm_virtual_machine_extension" "ama_windows" {
  for_each = local.vms_windows

  name                       = "AzureMonitorWindowsAgent"
  virtual_machine_id         = each.value
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.0"
  auto_upgrade_minor_version = true
  automatic_upgrade_enabled  = true
  tags                       = var.etiquetas
}

resource "azurerm_monitor_data_collection_rule_association" "linux" {
  for_each = local.vms_linux

  name                    = "dcra-${each.key}"
  target_resource_id      = each.value
  data_collection_rule_id = azurerm_monitor_data_collection_rule.linux.id

  depends_on = [azurerm_virtual_machine_extension.ama_linux]
}

resource "azurerm_monitor_data_collection_rule_association" "windows" {
  for_each = local.vms_windows

  name                    = "dcra-${each.key}"
  target_resource_id      = each.value
  data_collection_rule_id = azurerm_monitor_data_collection_rule.windows.id

  depends_on = [azurerm_virtual_machine_extension.ama_windows]
}

# ================= REGLAS ANALÍTICAS =================
locals {
  upns_emergencia = join(", ", [for u in azuread_user.emergencia : "\"${u.user_principal_name}\""])
}

resource "azurerm_sentinel_alert_rule_scheduled" "cuenta_emergencia" {
  name                       = "regla-cuenta-emergencia"
  log_analytics_workspace_id = local.sentinel_id
  display_name               = "Inicio de sesión con cuenta de emergencia"
  description                = "Cualquier uso de una cuenta de emergencia debe investigarse de inmediato."
  severity                   = "High"
  tactics                    = ["InitialAccess", "PrivilegeEscalation"]
  query_frequency            = "PT5M"
  query_period               = "PT10M"
  trigger_operator           = "GreaterThan"
  trigger_threshold          = 0

  query = <<-KQL
    SigninLogs
    | where UserPrincipalName in~ (${local.upns_emergencia})
    | project TimeGenerated, UserPrincipalName, UserId, IPAddress, Location, AppDisplayName, ResultType
  KQL

  entity_mapping {
    entity_type = "Account"
    field_mapping {
      identifier  = "FullName"
      column_name = "UserPrincipalName"
    }
    field_mapping {
      identifier  = "AadUserId"
      column_name = "UserId"
    }
  }

  entity_mapping {
    entity_type = "IP"
    field_mapping {
      identifier  = "Address"
      column_name = "IPAddress"
    }
  }
}

resource "azurerm_sentinel_alert_rule_scheduled" "idps_firewall" {
  name                       = "regla-idps-firewall"
  log_analytics_workspace_id = local.sentinel_id
  display_name               = "Firma de IDPS detectada en Azure Firewall"
  severity                   = "High"
  tactics                    = ["CommandAndControl", "LateralMovement"]
  query_frequency            = "PT5M"
  query_period               = "PT10M"
  trigger_operator           = "GreaterThan"
  trigger_threshold          = 0

  query = <<-KQL
    AZFWIdpsSignature
    | project TimeGenerated, SourceIp, DestinationIp, DestinationPort, Protocol, SignatureId, Description, Action, Severity
  KQL

  entity_mapping {
    entity_type = "IP"
    field_mapping {
      identifier  = "Address"
      column_name = "SourceIp"
    }
  }
}

resource "azurerm_sentinel_alert_rule_scheduled" "rafaga_waf" {
  name                       = "regla-rafaga-waf"
  log_analytics_workspace_id = local.sentinel_id
  display_name               = "Ráfaga de solicitudes bloqueadas por el WAF"
  severity                   = "Medium"
  tactics                    = ["InitialAccess"]
  query_frequency            = "PT5M"
  query_period               = "PT10M"
  trigger_operator           = "GreaterThan"
  trigger_threshold          = 0

  query = <<-KQL
    AGWFirewallLogs
    | where Action == "Blocked"
    | summarize Bloqueos = count(), Reglas = make_set(RuleId), Uris = make_set(RequestUri, 10) by ClientIp
    | where Bloqueos >= 10
  KQL

  entity_mapping {
    entity_type = "IP"
    field_mapping {
      identifier  = "Address"
      column_name = "ClientIp"
    }
  }
}

resource "azurerm_sentinel_alert_rule_scheduled" "fuerza_bruta_entra" {
  name                       = "regla-fuerza-bruta-entra"
  log_analytics_workspace_id = local.sentinel_id
  display_name               = "Fuerza bruta contra cuentas de Entra ID"
  severity                   = "High"
  tactics                    = ["CredentialAccess"]
  query_frequency            = "PT5M"
  query_period               = "PT10M"
  trigger_operator           = "GreaterThan"
  trigger_threshold          = 0

  # 50126: usuario o contraseña no válidos
  query = <<-KQL
    SigninLogs
    | where ResultType == "50126"
    | summarize Fallos = count(), IPs = make_set(IPAddress) by UserPrincipalName, UserId
    | where Fallos >= 5
  KQL

  entity_mapping {
    entity_type = "Account"
    field_mapping {
      identifier  = "FullName"
      column_name = "UserPrincipalName"
    }
    field_mapping {
      identifier  = "AadUserId"
      column_name = "UserId"
    }
  }
}
