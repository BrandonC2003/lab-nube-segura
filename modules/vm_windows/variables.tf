variable "nombre" {
  description = "Nombre de la VM (Windows limita el nombre de equipo a 15 caracteres)"
  type        = string

  validation {
    condition     = length(var.nombre) <= 15
    error_message = "El nombre de una VM Windows no puede pasar de 15 caracteres."
  }
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
  default = "Standard_F1as_v7"
}

variable "usuario_admin" {
  type    = string
  default = "azureadmin"
}

variable "script_inicio" {
  description = "Script de PowerShell que se ejecuta una vez al crear la VM (null = ninguno)"
  type        = string
  default     = null
}

variable "variables_script" {
  description = "Variables de PowerShell que se definen antes del script de inicio (p. ej. contraseñas)"
  type        = map(string)
  default     = {}
  sensitive   = true
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
