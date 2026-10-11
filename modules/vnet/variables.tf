variable "nombre" {
  description = "Nombre de la red virtual"
  type        = string
}

variable "grupo_recursos" {
  description = "Grupo de recursos donde se crea la VNet"
  type        = string
}

variable "ubicacion" {
  type = string
}

variable "espacio_direcciones" {
  description = "Rangos CIDR de la VNet"
  type        = list(string)
}

variable "etiquetas" {
  type    = map(string)
  default = {}
}

variable "subredes" {
  description = "Subredes de la VNet, con su NSG y reglas opcionales"
  type = map(object({
    prefijo            = string
    con_nsg            = optional(bool, true)
    endpoints_privados = optional(bool, false)
    reglas_nsg = optional(list(object({
      nombre    = string
      prioridad = number
      acceso    = string       # "Allow" o "Deny"
      puertos   = list(string) # ["443"], ["22", "3389"] o ["*"]
      origen    = string       # CIDR o etiqueta como "VirtualNetwork"
      destino   = optional(string, "*")
      protocolo = optional(string, "Tcp")
      direccion = optional(string, "Inbound")
    })), [])
  }))
}