locals {
  ip_web01  = "10.20.1.10"
  ip_erp01  = "10.20.1.20"
  ip_jump01 = "10.20.3.10"
}

# ================= CA INTERNA =================
# Firma los certificados internos; App Gateway la usa para validar el backend
resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem       = tls_private_key.ca.private_key_pem
  is_ca_certificate     = true
  validity_period_hours = 8760 # 1 año: suficiente para el prototipo

  subject {
    common_name  = "CA Interna Laboratorio"
    organization = "Prototipo UTEC"
  }

  allowed_uses = ["cert_signing", "crl_signing", "digital_signature"]
}

# ================= CERTIFICADO DE WEB01 =================
resource "tls_private_key" "web01" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "web01" {
  private_key_pem = tls_private_key.web01.private_key_pem
  dns_names       = ["web01.interno.lab", "app.interno.lab"]
  ip_addresses    = [local.ip_web01]

  subject {
    common_name  = "web01.interno.lab"
    organization = "Prototipo UTEC"
  }
}

resource "tls_locally_signed_cert" "web01" {
  cert_request_pem      = tls_cert_request.web01.cert_request_pem
  ca_private_key_pem    = tls_private_key.ca.private_key_pem
  ca_cert_pem           = tls_self_signed_cert.ca.cert_pem
  validity_period_hours = 8760

  allowed_uses = ["digital_signature", "key_encipherment", "server_auth"]
}

# ================= VM WEB01 (Juice Shop) =================
module "vm_web01" {
  source = "./modules/vm_linux"

  nombre            = "vm-web01"
  grupo_recursos    = local.rg_core
  ubicacion         = var.ubicacion
  subnet_id         = module.vnet_cargas.subredes["snet-apps"]
  ip_privada        = local.ip_web01
  tamano            = "Standard_B1ms" # Juice Shop necesita ~1 GB de RAM
  ssh_clave_publica = local.ssh_clave
  etiquetas         = var.etiquetas

  cloud_init = templatefile("${path.module}/cloud-init/web01.yaml.tftpl", {
    certificado   = tls_locally_signed_cert.web01.cert_pem
    llave_privada = tls_private_key.web01.private_key_pem
  })
}

# ================= VM JUMP01 (servidor de salto) =================
module "vm_jump01" {
  source = "./modules/vm_linux"

  nombre            = "vm-jump01"
  grupo_recursos    = local.rg_core
  ubicacion         = var.ubicacion
  subnet_id         = module.vnet_cargas.subredes["snet-gestion"]
  ip_privada        = local.ip_jump01
  ssh_clave_publica = local.ssh_clave
  cloud_init        = file("${path.module}/cloud-init/herramientas.yaml")
  etiquetas         = var.etiquetas
}

# ================= VM ERP01 (ERP simulado en IIS) =================
module "vm_erp01" {
  source = "./modules/vm_windows"

  nombre         = "vm-erp01"
  grupo_recursos = local.rg_core
  ubicacion      = var.ubicacion
  subnet_id      = module.vnet_cargas.subredes["snet-apps"]
  ip_privada     = local.ip_erp01
  script_inicio  = file("${path.module}/scripts/erp-inicio.ps1")
  etiquetas      = var.etiquetas
}

# Contraseña del administrador local custodiada en Key Vault
resource "azurerm_key_vault_secret" "erp01_admin" {
  name         = "vm-erp01-azureadmin"
  value        = module.vm_erp01.contrasena_admin
  key_vault_id = azurerm_key_vault.principal.id
  content_type = "contrasena-administrador-local"

  depends_on = [azurerm_role_assignment.kv_equipo]
}
