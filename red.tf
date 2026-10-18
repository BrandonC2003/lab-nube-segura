locals {
  rg_core    = azurerm_resource_group.rg["core"].name
  rango_sede = "192.168.0.0/16"
}

# ---------- Hub: 10.10.0.0/16 ----------
module "vnet_hub" {
  source = "./modules/vnet"

  nombre              = "vnet-${var.prefijo}-hub"
  grupo_recursos      = local.rg_core
  ubicacion           = var.ubicacion
  espacio_direcciones = ["10.10.0.0/16"]
  etiquetas           = var.etiquetas

  subredes = {
    AzureFirewallSubnet = { prefijo = "10.10.0.0/26", con_nsg = false }
    GatewaySubnet       = { prefijo = "10.10.1.0/27", con_nsg = false }
    snet-appgw = {
      prefijo = "10.10.2.0/24"
      # Reglas que exige Application Gateway v2 + publicación solo por HTTPS
      reglas_nsg = [
        { nombre = "permitir-gatewaymanager", prioridad = 100, acceso = "Allow", puertos = ["65200-65535"], origen = "GatewayManager" },
        { nombre = "permitir-azureloadbalancer", prioridad = 110, acceso = "Allow", protocolo = "*", puertos = ["*"], origen = "AzureLoadBalancer" },
        { nombre = "permitir-https-internet", prioridad = 120, acceso = "Allow", puertos = ["443"], origen = "Internet" },
      ]
    }
  }
}

# ---------- Spoke de cargas de trabajo: 10.20.0.0/16 ----------
module "vnet_cargas" {
  source = "./modules/vnet"

  nombre              = "vnet-${var.prefijo}-cargas"
  grupo_recursos      = local.rg_core
  ubicacion           = var.ubicacion
  espacio_direcciones = ["10.20.0.0/16"]
  etiquetas           = var.etiquetas

  subredes = {
    snet-apps = {
      prefijo = "10.20.1.0/24"
      reglas_nsg = [
        { nombre = "permitir-https-desde-appgw", prioridad = 100, acceso = "Allow", puertos = ["443"], origen = "10.10.2.0/24" },
        { nombre = "permitir-https-desde-sede", prioridad = 110, acceso = "Allow", puertos = ["443"], origen = local.rango_sede },
        { nombre = "permitir-admin-desde-gestion", prioridad = 120, acceso = "Allow", puertos = ["22", "3389"], origen = "10.20.3.0/24" },
        { nombre = "denegar-resto-vnet", prioridad = 4000, acceso = "Deny", protocolo = "*", puertos = ["*"], origen = "VirtualNetwork" },
      ]
    }

    snet-datos = {
      prefijo            = "10.20.2.0/24"
      endpoints_privados = true
      reglas_nsg = [
        { nombre = "permitir-sql-desde-apps", prioridad = 100, acceso = "Allow", puertos = ["1433"], origen = "10.20.1.0/24" },
        { nombre = "permitir-sql-desde-gestion", prioridad = 110, acceso = "Allow", puertos = ["1433"], origen = "10.20.3.0/24" },
        { nombre = "permitir-sql-desde-firewall", prioridad = 120, acceso = "Allow", puertos = ["1433"], origen = "10.10.0.0/26" },
        { nombre = "denegar-resto-vnet", prioridad = 4000, acceso = "Deny", protocolo = "*", puertos = ["*"], origen = "VirtualNetwork" },
      ]
    }

    snet-gestion = {
      prefijo = "10.20.3.0/24"
      reglas_nsg = [
        { nombre = "permitir-admin-desde-sede", prioridad = 100, acceso = "Allow", puertos = ["22", "3389"], origen = local.rango_sede },
        { nombre = "denegar-resto-vnet", prioridad = 4000, acceso = "Deny", protocolo = "*", puertos = ["*"], origen = "VirtualNetwork" },
      ]
    }

    snet-seguridad = {
      prefijo            = "10.20.4.0/24"
      endpoints_privados = true
      # Solo NSG: App Gateway llega a Key Vault directo por el peering (ruta /32 del punto de conexión)
      # y no a través de Azure Firewall; por ese camino no completaba la lectura del certificado y
      # el despliegue terminaba en InternalServerError. El NSG sigue limitando el origen.
      politicas_endpoints = "NetworkSecurityGroupEnabled"
      reglas_nsg = [
        { nombre = "permitir-keyvault-desde-cargas", prioridad = 100, acceso = "Allow", puertos = ["443"], origen = "10.20.0.0/16" },
        { nombre = "permitir-keyvault-desde-appgw", prioridad = 110, acceso = "Allow", puertos = ["443"], origen = "10.10.2.0/24" },
        { nombre = "denegar-resto-vnet", prioridad = 4000, acceso = "Deny", protocolo = "*", puertos = ["*"], origen = "VirtualNetwork" },
      ]
    }
  }
}

# ---------- Peering hub <-> spoke ----------
resource "azurerm_virtual_network_peering" "hub_a_cargas" {
  name                      = "peer-hub-a-cargas"
  resource_group_name       = local.rg_core
  virtual_network_name      = module.vnet_hub.nombre
  remote_virtual_network_id = module.vnet_cargas.id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = true
}

resource "azurerm_virtual_network_peering" "cargas_a_hub" {
  name                      = "peer-cargas-a-hub"
  resource_group_name       = local.rg_core
  virtual_network_name      = module.vnet_cargas.nombre
  remote_virtual_network_id = module.vnet_hub.id
  allow_forwarded_traffic   = true
  use_remote_gateways       = var.perimetro_activo # requiere que el VPN Gateway exista

  # Garantiza el orden de creación y destrucción respecto al VPN Gateway
  depends_on = [module.perimetro]
}

# IP del VPN Gateway en la capa persistente: se conserva entre despliegues del perímetro
resource "azurerm_public_ip" "vpn_gateway" {
  name                = "pip-${var.prefijo}-vpngw"
  location            = var.ubicacion
  resource_group_name = local.rg_core
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"] # requerido por la SKU VpnGw1AZ
  tags                = var.etiquetas
}