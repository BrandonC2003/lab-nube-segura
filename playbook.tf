# ================= PLAYBOOK: DESHABILITAR CUENTA COMPROMETIDA =================
# Logic App con disparador de incidente de Sentinel e identidad administrada.
# Se despliega como plantilla ARM porque la conexión de Sentinel con identidad
# administrada (parameterValueType = Alternative) no está disponible en azurerm_api_connection.
locals {
  playbook_nombre = "pb-${var.prefijo}-deshabilitar-usuario"
}

resource "azurerm_resource_group_template_deployment" "playbook" {
  name                = local.playbook_nombre
  resource_group_name = local.rg_core
  deployment_mode     = "Incremental"
  tags                = var.etiquetas

  parameters_content = jsonencode({
    nombre    = { value = local.playbook_nombre }
    ubicacion = { value = var.ubicacion }
  })

  template_content = jsonencode({
    "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"
    parameters = {
      nombre    = { type = "string" }
      ubicacion = { type = "string" }
    }
    variables = {
      conexion = "[concat('azuresentinel-', parameters('nombre'))]"
      api      = "[subscriptionResourceId('Microsoft.Web/locations/managedApis', parameters('ubicacion'), 'azuresentinel')]"
    }
    resources = [
      {
        type       = "Microsoft.Web/connections"
        apiVersion = "2016-06-01"
        name       = "[variables('conexion')]"
        location   = "[parameters('ubicacion')]"
        kind       = "V1"
        properties = {
          displayName        = "[variables('conexion')]"
          parameterValueType = "Alternative"
          api                = { id = "[variables('api')]" }
        }
      },
      {
        type       = "Microsoft.Logic/workflows"
        apiVersion = "2019-05-01"
        name       = "[parameters('nombre')]"
        location   = "[parameters('ubicacion')]"
        identity   = { type = "SystemAssigned" }
        dependsOn  = ["[resourceId('Microsoft.Web/connections', variables('conexion'))]"]
        properties = {
          state = "Enabled"
          definition = {
            "$schema"      = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
            contentVersion = "1.0.0.0"
            parameters = {
              "$connections" = { type = "Object", defaultValue = {} }
            }
            # Sentinel identifica el disparador de incidentes por este nombre
            triggers = {
              Microsoft_Sentinel_incident = {
                type = "ApiConnectionWebhook"
                inputs = {
                  host = { connection = { name = "@parameters('$connections')['azuresentinel']['connectionId']" } }
                  body = { callback_url = "@{listCallbackUrl()}" }
                  path = "/incident-creation"
                }
              }
            }
            actions = {
              Obtener_cuentas = {
                type     = "ApiConnection"
                runAfter = {}
                inputs = {
                  host   = { connection = { name = "@parameters('$connections')['azuresentinel']['connectionId']" } }
                  method = "post"
                  path   = "/entities/account"
                  body   = "@triggerBody()?['object']?['properties']?['relatedEntities']"
                }
              }
              Para_cada_cuenta = {
                type     = "Foreach"
                foreach  = "@body('Obtener_cuentas')?['Accounts']"
                runAfter = { Obtener_cuentas = ["Succeeded"] }
                actions = {
                  Deshabilitar_usuario = {
                    type = "Http"
                    inputs = {
                      method = "PATCH"
                      uri    = "https://graph.microsoft.com/v1.0/users/@{items('Para_cada_cuenta')?['AadUserId']}"
                      body   = { accountEnabled = false }
                      authentication = {
                        type     = "ManagedServiceIdentity"
                        audience = "https://graph.microsoft.com"
                      }
                    }
                  }
                }
              }
              Comentar_incidente = {
                type     = "ApiConnection"
                runAfter = { Para_cada_cuenta = ["Succeeded", "Failed"] }
                inputs = {
                  host   = { connection = { name = "@parameters('$connections')['azuresentinel']['connectionId']" } }
                  method = "post"
                  path   = "/Incidents/Comment"
                  body = {
                    incidentArmId = "@triggerBody()?['object']?['id']"
                    message       = "<p>Playbook ${local.playbook_nombre}: resultado de la deshabilitación de cuentas: @{result('Para_cada_cuenta')?[0]?['status']}</p>"
                  }
                }
              }
            }
          }
          parameters = {
            "$connections" = {
              value = {
                azuresentinel = {
                  connectionId   = "[resourceId('Microsoft.Web/connections', variables('conexion'))]"
                  connectionName = "[variables('conexion')]"
                  id             = "[variables('api')]"
                  connectionProperties = {
                    authentication = { type = "ManagedServiceIdentity" }
                  }
                }
              }
            }
          }
        }
      }
    ]
    outputs = {
      id           = { type = "string", value = "[resourceId('Microsoft.Logic/workflows', parameters('nombre'))]" }
      principal_id = { type = "string", value = "[reference(resourceId('Microsoft.Logic/workflows', parameters('nombre')), '2019-05-01', 'full').identity.principalId]" }
    }
  })
}

locals {
  playbook_salidas      = jsondecode(azurerm_resource_group_template_deployment.playbook.output_content)
  playbook_id           = local.playbook_salidas.id.value
  playbook_principal_id = local.playbook_salidas.principal_id.value
}

# ---------- Permisos del playbook ----------
# Microsoft Graph: User.ReadWrite.All (no alcanza a cuentas con roles de administrador)
data "azuread_service_principal" "graph" {
  client_id = "00000003-0000-0000-c000-000000000000"
}

resource "azuread_app_role_assignment" "playbook_graph" {
  app_role_id         = data.azuread_service_principal.graph.app_role_ids["User.ReadWrite.All"]
  principal_object_id = local.playbook_principal_id
  resource_object_id  = data.azuread_service_principal.graph.object_id
}

# Leer entidades y comentar incidentes
resource "azurerm_role_assignment" "playbook_sentinel" {
  scope                = azurerm_log_analytics_workspace.principal.id
  role_definition_name = "Microsoft Sentinel Responder"
  principal_id         = local.playbook_principal_id
}

# Sentinel necesita permiso para ejecutar playbooks del grupo de recursos
data "azuread_service_principal" "sentinel" {
  client_id = "98785600-1bb7-4fb9-b9fa-19afe2c8a360" # Azure Security Insights
}

resource "azurerm_role_assignment" "sentinel_automatizacion" {
  scope                = azurerm_resource_group.rg["core"].id
  role_definition_name = "Microsoft Sentinel Automation Contributor"
  principal_id         = data.azuread_service_principal.sentinel.object_id
}

# ---------- Regla de automatización ----------
# Solo para fuerza bruta: las cuentas de emergencia generan incidente pero no se deshabilitan
resource "random_uuid" "regla_automatizacion" {}

resource "azurerm_sentinel_automation_rule" "deshabilitar_fuerza_bruta" {
  name                       = random_uuid.regla_automatizacion.result
  log_analytics_workspace_id = local.sentinel_id
  display_name               = "Deshabilitar cuenta ante fuerza bruta"
  order                      = 1
  triggers_on                = "Incidents"
  triggers_when              = "Created"

  condition_json = jsonencode([
    {
      conditionType = "Property"
      conditionProperties = {
        propertyName   = "IncidentRelatedAnalyticRuleIds"
        operator       = "Contains"
        propertyValues = [azurerm_sentinel_alert_rule_scheduled.fuerza_bruta_entra.id]
      }
    }
  ])

  action_playbook {
    order        = 1
    logic_app_id = local.playbook_id
    tenant_id    = data.azurerm_client_config.actual.tenant_id
  }

  depends_on = [azurerm_role_assignment.sentinel_automatizacion]
}
