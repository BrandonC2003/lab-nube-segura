# ================= VPN DE SITIO A SITIO (IPsec IKEv2) =================
resource "azurerm_virtual_network_gateway" "this" {
  name                = "vgw-${var.prefijo}"
  location            = var.ubicacion
  resource_group_name = var.grupo_recursos_red
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = "VpnGw1AZ"
  generation          = "Generation1"
  active_active       = false
  tags                = var.etiquetas

  ip_configuration {
    name                          = "ipconfig1"
    public_ip_address_id          = var.ip_publica_vpn_id
    private_ip_address_allocation = "Dynamic"
    subnet_id                     = var.subred_gateway_id
  }
}

# Router de la sede y redes que publica
resource "azurerm_local_network_gateway" "sede" {
  name                = "lgw-${var.prefijo}-sede"
  location            = var.ubicacion
  resource_group_name = var.grupo_recursos
  gateway_address     = var.ip_publica_sede
  address_space       = [var.rangos.sede]
  tags                = var.etiquetas
}

resource "azurerm_virtual_network_gateway_connection" "sede" {
  name                       = "con-${var.prefijo}-sede"
  location                   = var.ubicacion
  resource_group_name        = var.grupo_recursos
  type                       = "IPsec"
  connection_protocol        = "IKEv2"
  virtual_network_gateway_id = azurerm_virtual_network_gateway.this.id
  local_network_gateway_id   = azurerm_local_network_gateway.sede.id
  shared_key                 = var.vpn_psk
  tags                       = var.etiquetas

  # Política IPsec explícita; coincide con "aes256-sha256-modp2048" de router-sede.yaml.tftpl
  ipsec_policy {
    ike_encryption   = "AES256"
    ike_integrity    = "SHA256"
    dh_group         = "DHGroup14" # modp2048
    ipsec_encryption = "AES256"
    ipsec_integrity  = "SHA256"
    pfs_group        = "PFS2048" # modp2048
    sa_lifetime      = 27000
  }
}
