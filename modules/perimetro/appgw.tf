# ================= APPLICATION GATEWAY WAF_v2 =================
resource "azurerm_public_ip" "appgw" {
  name                = "pip-${var.prefijo}-appgw"
  location            = var.ubicacion
  resource_group_name = var.grupo_recursos
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.etiquetas
}

# WAF en modo Prevención: bloquea (403), no solo registra (prueba V7)
resource "azurerm_web_application_firewall_policy" "this" {
  name                = "wafp-${var.prefijo}"
  location            = var.ubicacion
  resource_group_name = var.grupo_recursos
  tags                = var.etiquetas

  policy_settings {
    enabled            = true
    mode               = "Prevention"
    request_body_check = true
  }

  managed_rules {
    managed_rule_set {
      type    = "Microsoft_DefaultRuleSet" # DRS: sucesor del CRS de OWASP
      version = "2.1"
    }
  }
}

locals {
  appgw = {
    ip_frontend  = "frontend-publico"
    puerto_https = "puerto-443"
    certificado  = "cert-listener"
    listener     = "listener-https"
    pool         = "pool-web01"
    ajustes      = "ajustes-https-web01"
    sonda        = "sonda-https-web01"
    ca_backend   = "ca-interna"
    regla        = "regla-web01"
  }
}

resource "azurerm_application_gateway" "this" {
  name                = "agw-${var.prefijo}"
  location            = var.ubicacion
  resource_group_name = var.grupo_recursos
  firewall_policy_id  = azurerm_web_application_firewall_policy.this.id
  tags                = var.etiquetas

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 1 # una instancia fija: suficiente para el prototipo
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [var.appgw_identidad_id]
  }

  # Solo TLS 1.2 o superior hacia Internet
  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101"
  }

  gateway_ip_configuration {
    name      = "ipconfig-appgw"
    subnet_id = var.subred_appgw_id
  }

  frontend_ip_configuration {
    name                 = local.appgw.ip_frontend
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  frontend_port {
    name = local.appgw.puerto_https
    port = 443
  }

  # Sesión TLS 1: cliente -> WAF
  ssl_certificate {
    name                = local.appgw.certificado
    key_vault_secret_id = var.appgw_certificado_secret_id
  }

  http_listener {
    name                           = local.appgw.listener
    frontend_ip_configuration_name = local.appgw.ip_frontend
    frontend_port_name             = local.appgw.puerto_https
    protocol                       = "Https"
    ssl_certificate_name           = local.appgw.certificado
  }

  backend_address_pool {
    name         = local.appgw.pool
    ip_addresses = [var.ip_web01]
  }

  # Sesión TLS 2: WAF -> web01, validando que el certificado lo firmó la CA interna
  trusted_root_certificate {
    name = local.appgw.ca_backend
    data = base64encode(var.ca_interna_pem)
  }

  backend_http_settings {
    name                           = local.appgw.ajustes
    protocol                       = "Https"
    port                           = 443
    host_name                      = var.host_web01
    cookie_based_affinity          = "Disabled"
    request_timeout                = 30
    probe_name                     = local.appgw.sonda
    trusted_root_certificate_names = [local.appgw.ca_backend]
  }

  probe {
    name                                      = local.appgw.sonda
    protocol                                  = "Https"
    path                                      = "/"
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200-399"]
    }
  }

  request_routing_rule {
    name                       = local.appgw.regla
    rule_type                  = "Basic"
    priority                   = 100
    http_listener_name         = local.appgw.listener
    backend_address_pool_name  = local.appgw.pool
    backend_http_settings_name = local.appgw.ajustes
  }

  depends_on = [
    azurerm_subnet_route_table_association.appgw,
    azurerm_firewall_policy_rule_collection_group.this,
  ]
}
