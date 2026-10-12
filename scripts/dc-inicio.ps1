# Controlador de dominio del bosque lab.local (identidad híbrida con Entra Cloud Sync)
# Variables definidas por Terraform antes de este script: $ContrasenaDsrm

Install-WindowsFeature AD-Domain-Services -IncludeManagementTools

# Tras el reinicio: reenviador hacia el DNS de Azure para resolver las zonas privadas
$tarea = @'
Set-DnsServerForwarder -IPAddress 168.63.129.16
Unregister-ScheduledTask -TaskName 'ReenviadorDnsAzure' -Confirm:$false
'@
Set-Content -Path 'C:\Windows\Temp\reenviador-dns.ps1' -Value $tarea
$accion = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument '-ExecutionPolicy Bypass -File C:\Windows\Temp\reenviador-dns.ps1'
$disparador = New-ScheduledTaskTrigger -AtStartup
Register-ScheduledTask -TaskName 'ReenviadorDnsAzure' -Action $accion -Trigger $disparador -User 'SYSTEM' -RunLevel Highest

Install-ADDSForest `
  -DomainName 'lab.local' `
  -DomainNetbiosName 'LAB' `
  -InstallDns `
  -SafeModeAdministratorPassword (ConvertTo-SecureString $ContrasenaDsrm -AsPlainText -Force) `
  -NoRebootOnCompletion `
  -Force

# Reinicio diferido para que la extensión reporte el resultado antes
shutdown.exe /r /t 120 /c "Promocion a controlador de dominio"

# Permite ping de entrada para las pruebas de conectividad
New-NetFirewallRule -DisplayName "Permitir ICMPv4 de entrada" -Protocol ICMPv4 -IcmpType 8 -Direction Inbound -Action Allow
