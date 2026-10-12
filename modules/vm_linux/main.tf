resource "azurerm_network_interface" "this" {
  name                  = "nic-${var.nombre}"
  location              = var.ubicacion
  resource_group_name   = var.grupo_recursos
  ip_forwarding_enabled = var.reenvio_ip
  tags                  = var.etiquetas

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.ip_privada
    public_ip_address_id          = var.ip_publica_id
  }
}

resource "azurerm_linux_virtual_machine" "this" {
  name                            = var.nombre
  location                        = var.ubicacion
  resource_group_name             = var.grupo_recursos
  size                            = var.tamano
  admin_username                  = var.usuario_admin
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.this.id]
  custom_data                     = var.cloud_init == null ? null : base64encode(var.cloud_init)
  tags                            = var.etiquetas

  admin_ssh_key {
    username   = var.usuario_admin
    public_key = var.ssh_clave_publica
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "ubuntu-24_04-lts"
    sku       = "server"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned" # la usará el agente de monitoreo en la lección 8
  }

  boot_diagnostics {} # habilita la consola serie
}