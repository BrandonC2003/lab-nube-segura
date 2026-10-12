# ERP simulado: IIS con una página que identifica al servidor
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
New-NetFirewallRule -DisplayName "Permitir ICMPv4 de entrada" -Protocol ICMPv4 -IcmpType 8 -Direction Inbound -Action Allow
