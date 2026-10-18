locals {
  rg_sede        = azurerm_resource_group.rg["sede"].name
  ip_router_sede = "192.168.0.4" # primera IP utilizable
  ssh_clave      = file(pathexpand(var.ssh_clave_publica))
}

# ---------- Clave compartida de la VPN ----------
resource "random_password" "vpn_psk" {
  length  = 32
  special = false
}

# ---------- IP pública del router de la sede ----------
resource "azurerm_public_ip" "router_sede" {
  name                = "pip-${var.prefijo}-router-sede"
  location            = var.ubicacion_sede
  resource_group_name = local.rg_sede
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.etiquetas
}

# ---------- Red de la sede: 192.168.0.0/16 ----------
# En otra región: el túnel IPsec cruza Internet, como entre una oficina y la nube
module "vnet_sede" {
  source = "./modules/vnet"

  nombre              = "vnet-${var.prefijo}-sede"
  grupo_recursos      = local.rg_sede
  ubicacion           = var.ubicacion_sede
  espacio_direcciones = [local.rango_sede]
  etiquetas           = var.etiquetas

  subredes = {
    snet-borde = {
      prefijo = "192.168.0.0/24"
      reglas_nsg = [
        { nombre = "permitir-ike-desde-azure", prioridad = 100, acceso = "Allow", protocolo = "Udp", puertos = ["500", "4500"], origen = azurerm_public_ip.vpn_gateway.ip_address },
        { nombre = "permitir-ssh-administrador", prioridad = 110, acceso = "Allow", puertos = ["22"], origen = var.ip_admin },
      ]
    }
    vlan-administrativa = { prefijo = "192.168.10.0/24" }
    vlan-operativa      = { prefijo = "192.168.20.0/24" }
    vlan-servidores     = { prefijo = "192.168.30.0/24" }
    vlan-identidad      = { prefijo = "192.168.40.0/24" }
  }
}

# ---------- Rutas: las VLAN salen hacia Azure por el router ----------
resource "azurerm_route_table" "sede" {
  name                          = "rt-${var.prefijo}-sede-vlans"
  location                      = var.ubicacion_sede
  resource_group_name           = local.rg_sede
  bgp_route_propagation_enabled = false
  tags                          = var.etiquetas

  route {
    name                   = "hacia-hub"
    address_prefix         = "10.10.0.0/16"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.ip_router_sede
  }

  route {
    name                   = "hacia-cargas"
    address_prefix         = "10.20.0.0/16"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = local.ip_router_sede
  }
}

resource "azurerm_subnet_route_table_association" "sede" {
  for_each = toset(["vlan-administrativa", "vlan-operativa", "vlan-servidores", "vlan-identidad"])

  subnet_id      = module.vnet_sede.subredes[each.key]
  route_table_id = azurerm_route_table.sede.id
}

# ---------- Router strongSwan ----------
module "vm_router_sede" {
  source = "./modules/vm_linux"

  nombre            = "vm-gw-sede"
  grupo_recursos    = local.rg_sede
  ubicacion         = var.ubicacion_sede
  subnet_id         = module.vnet_sede.subredes["snet-borde"]
  ip_privada        = local.ip_router_sede
  ip_publica_id     = azurerm_public_ip.router_sede.id
  reenvio_ip        = true
  tamano            = var.tamano_vm_linux
  hora_apagado      = var.hora_apagado_vms
  ssh_clave_publica = local.ssh_clave
  etiquetas         = var.etiquetas

  cloud_init = templatefile("${path.module}/cloud-init/router-sede.yaml.tftpl", {
    ip_local        = local.ip_router_sede
    ip_publica_sede = azurerm_public_ip.router_sede.ip_address
    ip_vpn_azure    = azurerm_public_ip.vpn_gateway.ip_address
    psk             = random_password.vpn_psk.result
    rango_sede      = local.rango_sede
    rangos_azure    = "10.10.0.0/16,10.20.0.0/16"
  })
}

# ---------- Equipos de prueba en las VLAN ----------
locals {
  equipos_sede = {
    vm-admin01 = { subred = "vlan-administrativa", ip = "192.168.10.10" }
    vm-srv01   = { subred = "vlan-servidores", ip = "192.168.30.10" }
  }
}

# Certificado del servicio local que asume app.interno.lab durante la reversión (V11)
resource "tls_private_key" "srv01" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "srv01" {
  private_key_pem = tls_private_key.srv01.private_key_pem
  dns_names       = ["app.interno.lab", "srv01.interno.lab"]
  ip_addresses    = ["192.168.30.10"]

  subject {
    common_name  = "app.interno.lab"
    organization = "Prototipo UTEC"
  }
}

resource "tls_locally_signed_cert" "srv01" {
  cert_request_pem      = tls_cert_request.srv01.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = 8760

  allowed_uses = ["digital_signature", "key_encipherment", "server_auth"]
}

locals {
  cloud_init_sede = {
    vm-admin01 = file("${path.module}/cloud-init/herramientas.yaml")
    vm-srv01 = templatefile("${path.module}/cloud-init/srv01.yaml.tftpl", {
      certificado   = tls_locally_signed_cert.srv01.cert_pem
      llave_privada = tls_private_key.srv01.private_key_pem
    })
  }
}

module "vm_sede" {
  source   = "./modules/vm_linux"
  for_each = local.equipos_sede

  nombre            = each.key
  grupo_recursos    = local.rg_sede
  ubicacion         = var.ubicacion_sede
  subnet_id         = module.vnet_sede.subredes[each.value.subred]
  ip_privada        = each.value.ip
  tamano            = var.tamano_vm_linux
  hora_apagado      = var.hora_apagado_vms
  ssh_clave_publica = local.ssh_clave
  cloud_init        = local.cloud_init_sede[each.key]
  etiquetas         = var.etiquetas
}