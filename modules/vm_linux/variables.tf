variable "nombre" {
  type = string
}

variable "grupo_recursos" {
  type = string
}

variable "ubicacion" {
  type = string
}

variable "subnet_id" {
  description = "ID de la subred donde se conecta la VM"
  type        = string
}

variable "ip_privada" {
  description = "IP privada fija de la VM"
  type        = string
}

variable "tamano" {
  type    = string
  default = "Standard_F1als_v7"
}

variable "usuario_admin" {
  type    = string
  default = "azureadmin"
}

variable "ssh_clave_publica" {
  description = "Contenido de la llave pública SSH"
  type        = string
}

variable "ip_publica_id" {
  description = "ID de una IP pública ya creada (null = sin IP pública)"
  type        = string
  default     = null
}

variable "reenvio_ip" {
  description = "Permite que la VM reenvíe tráfico que no es para ella (necesario en routers)"
  type        = bool
  default     = false
}

variable "cloud_init" {
  description = "Configuración cloud-init en texto plano (null = ninguna)"
  type        = string
  default     = null
}

variable "controlador_disco" {
  description = "Controlador de disco: NVMe (obligatorio en tamaños v6/v7) o SCSI"
  type        = string
  default     = "NVMe"
}

variable "hora_apagado" {
  description = "Hora de apagado automático diario en formato HHMM (null = sin apagado)"
  type        = string
  default     = null
}

variable "zona_horaria" {
  description = "Zona horaria del apagado automático"
  type        = string
  default     = "Central America Standard Time"
}

variable "etiquetas" {
  type    = map(string)
  default = {}
}