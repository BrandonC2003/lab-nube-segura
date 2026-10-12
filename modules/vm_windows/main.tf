# Contraseña única por VM; nunca se escribe a mano ni se repite entre equipos
resource "random_password" "admin" {
  length           = 24
  special          = true
  override_special = "!#%*-_=+" # evita caracteres que rompen JSON o PowerShell
  min_lower        = 2
  min_upper        = 2
  min_numeric      = 2
  min_special      = 2
}

resource "azurerm_network_interface" "this" {
  name                = "nic-${var.nombre}"
  location            = var.ubicacion
  resource_group_name = var.grupo_recursos
  tags                = var.etiquetas

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.ip_privada
  }
}

resource "azurerm_windows_virtual_machine" "this" {
  name                  = var.nombre
  location              = var.ubicacion
  resource_group_name   = var.grupo_recursos
  size                  = var.tamano
  admin_username        = var.usuario_admin
  admin_password        = random_password.admin.result
  network_interface_ids = [azurerm_network_interface.this.id]
  tags                  = var.etiquetas

  # Parches gestionados por Azure: alimenta el indicador de parches (Tabla 10)
  patch_mode            = "AutomaticByPlatform"
  patch_assessment_mode = "AutomaticByPlatform"

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-azure-edition"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned" # acceso a SQL sin contraseña y agente de monitoreo
  }

  boot_diagnostics {} # habilita la consola serie
}

# Solo se crea si se pasó un script (count = 0 o 1)
resource "azurerm_virtual_machine_extension" "script_inicio" {
  count = var.script_inicio == null ? 0 : 1

  name                 = "script-inicio"
  virtual_machine_id   = azurerm_windows_virtual_machine.this.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  tags                 = var.etiquetas

  # -EncodedCommand espera Base64 de texto UTF-16LE; así no hay problemas de comillas.
  # protected_settings se cifra en Azure y no aparece en el portal.
  protected_settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -EncodedCommand ${textencodebase64(var.script_inicio, "UTF-16LE")}"
  })
}
