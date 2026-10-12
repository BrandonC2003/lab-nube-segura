variable "prefijo" {
  type = string
}

variable "ubicacion" {
  type = string
}

variable "grupo_recursos" {
  description = "Grupo efímero (rg-proto-perimetro): App Gateway, políticas, rutas, IPs públicas"
  type        = string
}

variable "grupo_recursos_red" {
  description = "Grupo de la VNet hub: el Firewall y el VPN Gateway deben vivir junto a su VNet"
  type        = string
}

variable "etiquetas" {
  type    = map(string)
  default = {}
}

# ---------- Subredes ----------
variable "subred_firewall_id" {
  type = string
}

variable "subred_gateway_id" {
  type = string
}

variable "subred_appgw_id" {
  type = string
}

variable "subredes_spoke_ids" {
  description = "IDs de las subredes del spoke que deben salir por el Firewall"
  type        = map(string)
}

variable "rangos" {
  description = "Rangos CIDR usados en reglas y rutas"
  type = object({
    sede      = string
    cargas    = string
    apps      = string
    datos     = string
    gestion   = string
    seguridad = string
    appgw     = string
  })
}

# ---------- VPN ----------
variable "ip_publica_vpn_id" {
  description = "IP pública persistente del VPN Gateway (vive en rg-proto-core)"
  type        = string
}

variable "ip_publica_sede" {
  description = "IP pública del router strongSwan de la sede"
  type        = string
}

variable "vpn_psk" {
  type      = string
  sensitive = true
}

# ---------- Application Gateway ----------
variable "ip_web01" {
  type = string
}

variable "host_web01" {
  description = "Nombre que debe coincidir con el certificado de web01 (SNI y validación)"
  type        = string
}

variable "ca_interna_pem" {
  description = "Certificado de la CA interna; App Gateway solo confía en backends firmados por ella"
  type        = string
}

variable "appgw_identidad_id" {
  description = "Identidad administrada asignada por el usuario con permiso de lectura de secretos en Key Vault"
  type        = string
}

variable "appgw_certificado_secret_id" {
  description = "ID sin versión del secreto del certificado del listener (permite renovación automática)"
  type        = string
}
