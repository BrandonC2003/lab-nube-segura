variable "subscription_id" {
  description = "ID de la suscripcion de Azure donde se despliega el laboratorio"
  type        = string
}

variable "ubicacion" {
  description = "Region de Azure"
  type        = string
  default     = "eastus"
}

variable "prefijo" {
  description = "Prefijo para nombrar los recursos"
  type        = string
  default     = "proto"
}

variable "etiquetas" {
  description = "Etiquetas comunes para todos los recursos"
  type        = map(string)
  default = {
    proyecto = "modelo-seguridad-nube"
    entorno  = "prototipo"
    gestion  = "terraform"
  }
}

variable "perimetro_activo" {
  description = "Si es true, se despliega la capa cara (Firewall, App Gateway, VPN Gateway)"
  type        = bool
  default     = false
}

variable "ssh_clave_publica" {
  description = "Ruta a la llave pública SSH"
  type        = string
  default     = "~/.ssh/lab_azure.pub"
}

variable "ip_admin" {
  description = "IP pública en formato CIDR (ej. 190.86.1.2/32), única autorizada para SSH"
  type        = string
}