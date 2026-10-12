# ================= IDENTIDAD Y CERTIFICADO DEL APP GATEWAY =================
# Persistentes: se conservan entre despliegues del perímetro.

# Identidad con la que App Gateway lee su certificado de Key Vault
resource "azurerm_user_assigned_identity" "appgw" {
  name                = "id-${var.prefijo}-appgw"
  location            = var.ubicacion
  resource_group_name = local.rg_core
  tags                = var.etiquetas
}

# Mínimo privilegio: solo leer secretos (el certificado se entrega como secreto PFX)
resource "azurerm_role_assignment" "kv_appgw" {
  scope                = azurerm_key_vault.principal.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.appgw.principal_id
}

# Certificado público del WAF (sesión TLS 1), autofirmado y con renovación automática
resource "azurerm_key_vault_certificate" "appgw" {
  name         = "cert-appgw"
  key_vault_id = azurerm_key_vault.principal.id
  tags         = var.etiquetas

  certificate_policy {
    issuer_parameters {
      name = "Self"
    }

    key_properties {
      exportable = true # App Gateway necesita la llave privada
      key_type   = "RSA"
      key_size   = 2048
      reuse_key  = false
    }

    secret_properties {
      content_type = "application/x-pkcs12"
    }

    x509_certificate_properties {
      subject            = "CN=juiceshop.proto.lab"
      validity_in_months = 12
      key_usage          = ["digitalSignature", "keyEncipherment"]
      extended_key_usage = ["1.3.6.1.5.5.7.3.1"] # autenticación de servidor

      subject_alternative_names {
        dns_names = ["juiceshop.proto.lab"]
      }
    }

    lifetime_action {
      action {
        action_type = "AutoRenew"
      }
      trigger {
        days_before_expiry = 30
      }
    }
  }

  depends_on = [azurerm_role_assignment.kv_equipo]
}

# ================= PERÍMETRO =================
# Capa de mayor costo: solo se despliega con perimetro_activo = true.
module "perimetro" {
  source = "./modules/perimetro"
  count  = var.perimetro_activo ? 1 : 0

  prefijo            = var.prefijo
  ubicacion          = var.ubicacion
  grupo_recursos     = azurerm_resource_group.rg["perimetro"].name
  grupo_recursos_red = local.rg_core
  etiquetas          = var.etiquetas

  subred_firewall_id = module.vnet_hub.subredes["AzureFirewallSubnet"]
  subred_gateway_id  = module.vnet_hub.subredes["GatewaySubnet"]
  subred_appgw_id    = module.vnet_hub.subredes["snet-appgw"]
  subredes_spoke_ids = module.vnet_cargas.subredes

  rangos = {
    sede      = local.rango_sede
    cargas    = "10.20.0.0/16"
    apps      = "10.20.1.0/24"
    datos     = "10.20.2.0/24"
    gestion   = "10.20.3.0/24"
    seguridad = "10.20.4.0/24"
    appgw     = "10.10.2.0/24"
  }

  ip_publica_vpn_id = azurerm_public_ip.vpn_gateway.id
  ip_publica_sede   = azurerm_public_ip.router_sede.ip_address
  vpn_psk           = random_password.vpn_psk.result

  ip_web01       = local.ip_web01
  host_web01     = "web01.interno.lab"
  ca_interna_pem = tls_self_signed_cert.ca.cert_pem

  appgw_identidad_id          = azurerm_user_assigned_identity.appgw.id
  appgw_certificado_secret_id = azurerm_key_vault_certificate.appgw.versionless_secret_id

  depends_on = [azurerm_role_assignment.kv_appgw]
}
