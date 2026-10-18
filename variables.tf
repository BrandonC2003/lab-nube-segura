variable "subscription_id" {
  description = "ID de la suscripcion de Azure donde se despliega el laboratorio"
  type        = string
}

variable "ubicacion" {
  description = "Region de Azure"
  type        = string
  default     = "eastus"
}

variable "ubicacion_sede" {
  description = "Región de la sede simulada (separada de la nube por la cuota de vCPU por región)"
  type        = string
  default     = "eastus2"
}

variable "tamano_vm_linux" {
  description = "Tamaño de las VMs Linux"
  type        = string
  default     = "Standard_F1als_v7"
}

variable "tamano_vm_windows" {
  description = "Tamaño de las VMs Windows"
  type        = string
  default     = "Standard_F1as_v7"
}

variable "hora_apagado_vms" {
  description = "Hora de apagado automático diario de las VMs (HHMM, hora de El Salvador; null = desactivado)"
  type        = string
  default     = "2300"
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

variable "administradores_lab" {
  description = "Object IDs de Entra ID de los integrantes del equipo"
  type        = list(string)
}

variable "ips_equipo" {
  description = "IPs públicas adicionales de los compañeros (CIDR), con acceso al Key Vault"
  type        = list(string)
  default     = []
}

variable "waf_reglas_deshabilitadas" {
  description = "Reglas del WAF desactivadas por falso positivo, por grupo (p. ej. { \"SQLI\" = [\"942430\"] })"
  type        = map(list(string))
  default     = {}
}

variable "waf_exclusiones" {
  description = "Exclusiones del WAF por falso positivo"
  type = list(object({
    variable = string
    operador = string
    selector = string
  }))
  default = []
}

variable "servicio_app_activo" {
  description = "Destino de app.interno.lab: \"nube\" (vm-web01) o \"local\" (vm-srv01, plan de reversión V11)"
  type        = string
  default     = "nube"

  validation {
    condition     = contains(["nube", "local"], var.servicio_app_activo)
    error_message = "Valores válidos: nube o local."
  }
}

variable "estado_acceso_condicional" {
  description = "Estado de las políticas de acceso condicional: primero solo informe, luego activadas"
  type        = string
  default     = "enabledForReportingButNotEnforced"

  validation {
    condition     = contains(["enabledForReportingButNotEnforced", "enabled", "disabled"], var.estado_acceso_condicional)
    error_message = "Valores válidos: enabledForReportingButNotEnforced, enabled o disabled."
  }
}
