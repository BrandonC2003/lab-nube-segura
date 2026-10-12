# ================= AZURE FIREWALL PREMIUM =================
resource "azurerm_public_ip" "firewall" {
  name                = "pip-${var.prefijo}-fw"
  location            = var.ubicacion
  resource_group_name = var.grupo_recursos
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.etiquetas
}

resource "azurerm_firewall_policy" "this" {
  name                     = "afwp-${var.prefijo}"
  location                 = var.ubicacion
  resource_group_name      = var.grupo_recursos
  sku                      = "Premium"
  threat_intelligence_mode = "Deny" # bloquea IPs/dominios maliciosos conocidos
  tags                     = var.etiquetas

  # IDPS: alerta y bloquea por firmas (prueba V8)
  intrusion_detection {
    mode = "Deny"
  }
}

resource "azurerm_firewall_policy_rule_collection_group" "this" {
  name               = "rcg-${var.prefijo}"
  firewall_policy_id = azurerm_firewall_policy.this.id
  priority           = 100

  # ---------- Tráfico este-oeste: segmentación entre sede, hub y spoke ----------
  # Lo que no aparece aquí se deniega (p. ej. VLAN administrativa -> SQL, prueba V6)
  network_rule_collection {
    name     = "segmentacion"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "sede-a-apps-https"
      protocols             = ["TCP"]
      source_addresses      = [var.rangos.sede]
      destination_addresses = [var.rangos.apps]
      destination_ports     = ["443"]
    }

    rule {
      name                  = "sede-a-gestion-admin"
      protocols             = ["TCP"]
      source_addresses      = [var.rangos.sede]
      destination_addresses = [var.rangos.gestion]
      destination_ports     = ["22", "3389"]
    }

    rule {
      name                  = "gestion-a-apps-admin"
      protocols             = ["TCP"]
      source_addresses      = [var.rangos.gestion]
      destination_addresses = [var.rangos.apps]
      destination_ports     = ["22", "3389"]
    }

    rule {
      name                  = "apps-a-datos-sql"
      protocols             = ["TCP"]
      source_addresses      = [var.rangos.apps]
      destination_addresses = [var.rangos.datos]
      destination_ports     = ["1433"]
    }

    rule {
      name                  = "cargas-y-appgw-a-keyvault"
      protocols             = ["TCP"]
      source_addresses      = [var.rangos.cargas, var.rangos.appgw]
      destination_addresses = [var.rangos.seguridad]
      destination_ports     = ["443"]
    }

    rule {
      name                  = "appgw-a-web01"
      protocols             = ["TCP"]
      source_addresses      = [var.rangos.appgw]
      destination_addresses = [var.ip_web01]
      destination_ports     = ["443"]
    }
  }

  # ---------- Salida a Internet: solo destinos necesarios (lista blanca) ----------
  application_rule_collection {
    name     = "salida-internet"
    priority = 200
    action   = "Allow"

    rule {
      name             = "repositorios-ubuntu"
      source_addresses = [var.rangos.cargas]
      destination_fqdns = [
        "*.ubuntu.com",
        "azure.archive.ubuntu.com",
      ]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name             = "docker-hub"
      source_addresses = [var.rangos.cargas]
      destination_fqdns = [
        "*.docker.io",
        "*.docker.com",
        "production.cloudflare.docker.com",
      ]
      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name                  = "windows-update"
      source_addresses      = [var.rangos.cargas]
      destination_fqdn_tags = ["WindowsUpdate"]
      protocols {
        type = "Http"
        port = 80
      }
      protocols {
        type = "Https"
        port = 443
      }
    }

    # Conector de red privada (App Proxy). Lista de Microsoft Learn,
    # "How to configure connectors", revisada el 11/10/2026.
    rule {
      name             = "app-proxy-https"
      source_addresses = [var.rangos.apps]
      destination_fqdns = [
        "*.msappproxy.net",
        "*.servicebus.windows.net",
        "login.windows.net",
        "secure.aadcdn.microsoftonline-p.com",
        "*.microsoftonline.com",
        "*.microsoftonline-p.com",
        "*.msauth.net",
        "*.msauthimages.net",
        "*.msecnd.net",
        "*.msftauth.net",
        "*.msftauthimages.net",
        "*.phonefactor.net",
        "enterpriseregistration.windows.net",
        "management.azure.com",
        "ctldl.windowsupdate.com",
        "www.microsoft.com",
      ]
      protocols {
        type = "Https"
        port = 443
      }
    }

    rule {
      name             = "app-proxy-revocacion-http"
      source_addresses = [var.rangos.apps]
      destination_fqdns = [
        "crl3.digicert.com",
        "crl4.digicert.com",
        "ocsp.digicert.com",
        "crl.microsoft.com",
        "oneocsp.microsoft.com",
        "ocsp.msocsp.com",
        "ctldl.windowsupdate.com",
        "www.microsoft.com",
      ]
      protocols {
        type = "Http"
        port = 80
      }
    }

    # Azure Monitor Agent
    rule {
      name             = "azure-monitor-agent"
      source_addresses = [var.rangos.cargas]
      destination_fqdns = [
        "global.handler.control.monitor.azure.com",
        "*.handler.control.monitor.azure.com",
        "*.ingest.monitor.azure.com",
        "*.ods.opinsights.azure.com",
        "*.oms.opinsights.azure.com",
      ]
      protocols {
        type = "Https"
        port = 443
      }
    }
  }
}

resource "azurerm_firewall" "this" {
  name                = "afw-${var.prefijo}"
  location            = var.ubicacion
  resource_group_name = var.grupo_recursos_red
  sku_name            = "AZFW_VNet"
  sku_tier            = "Premium"
  firewall_policy_id  = azurerm_firewall_policy.this.id
  tags                = var.etiquetas

  ip_configuration {
    name                 = "ipconfig1"
    subnet_id            = var.subred_firewall_id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }

  # Las reglas deben existir antes de que el tráfico empiece a pasar por aquí
  depends_on = [azurerm_firewall_policy_rule_collection_group.this]
}

locals {
  ip_firewall = azurerm_firewall.this.ip_configuration[0].private_ip_address
}
