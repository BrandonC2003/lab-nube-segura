# ERP simulado: IIS con una página que identifica al servidor
# El enlace HTTPS lo configura erp-https.ps1 (Run Command), porque la extensión
# CustomScriptExtension limita la línea de comandos a 8191 caracteres.
# Idempotente: la extensión vuelve a ejecutarlo cuando cambia su contenido.
Install-WindowsFeature Web-Server -IncludeManagementTools

$html = @"
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>ERP simulado</title></head>
<body>
  <h1>ERP simulado</h1>
  <p>Servidor: $env:COMPUTERNAME</p>
  <p>Prototipo de factibilidad - modelo de seguridad para la adopcion de servicios en la nube</p>
</body>
</html>
"@
Set-Content -Path "C:\inetpub\wwwroot\index.html" -Value $html -Encoding UTF8

# Permite ping de entrada para las pruebas de conectividad (V2, V6)
if (-not (Get-NetFirewallRule -DisplayName "Permitir ICMPv4 de entrada" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -DisplayName "Permitir ICMPv4 de entrada" -Protocol ICMPv4 -IcmpType 8 -Direction Inbound -Action Allow
}

# Requisito del conector de red privada de Entra (App Proxy) en Windows Server 2019+
$winHttp = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp'
if (-not (Test-Path $winHttp)) { New-Item -Path $winHttp -Force | Out-Null }
Set-ItemProperty -Path $winHttp -Name 'EnableDefaultHTTP2' -Value 0 -Type DWord
