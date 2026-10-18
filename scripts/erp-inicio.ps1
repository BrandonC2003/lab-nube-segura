# ERP simulado: IIS con una página que identifica al servidor, publicado por HTTPS
# Variables definidas por Terraform antes de este script: $CertificadoPem, $LlavePem
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

# ---------- Certificado emitido por la CA interna ----------
# .NET Framework no importa llaves PEM; se convierte la llave PKCS#1 a RSAParameters.
Add-Type -TypeDefinition @'
using System;
using System.Security.Cryptography;

public static class Pkcs1
{
    public static byte[] DesdePem(string pem)
    {
        var b64 = System.Text.RegularExpressions.Regex.Replace(pem, "-----[^-]+-----|\\s", "");
        return Convert.FromBase64String(b64);
    }

    public static RSAParameters LeerLlave(byte[] der)
    {
        int i = 0;
        Encabezado(der, ref i, 0x30);             // SEQUENCE RSAPrivateKey
        LeerEntero(der, ref i);                    // version
        var n = LeerEntero(der, ref i);
        var e = LeerEntero(der, ref i);
        var d = LeerEntero(der, ref i);
        var p = LeerEntero(der, ref i);
        var q = LeerEntero(der, ref i);
        var dp = LeerEntero(der, ref i);
        var dq = LeerEntero(der, ref i);
        var iq = LeerEntero(der, ref i);
        int largo = n.Length, mitad = (largo + 1) / 2;
        return new RSAParameters {
            Modulus = n, Exponent = e, D = Ajustar(d, largo),
            P = Ajustar(p, mitad), Q = Ajustar(q, mitad),
            DP = Ajustar(dp, mitad), DQ = Ajustar(dq, mitad), InverseQ = Ajustar(iq, mitad)
        };
    }

    static int Encabezado(byte[] b, ref int i, byte etiqueta)
    {
        if (b[i++] != etiqueta) throw new FormatException("Llave PKCS#1 no valida");
        int largo = b[i++];
        if ((largo & 0x80) != 0)
        {
            int bytes = largo & 0x7F; largo = 0;
            for (int k = 0; k < bytes; k++) largo = (largo << 8) | b[i++];
        }
        return largo;
    }

    static byte[] LeerEntero(byte[] b, ref int i)
    {
        int largo = Encabezado(b, ref i, 0x02);
        int inicio = i; i += largo;
        while (largo > 1 && b[inicio] == 0) { inicio++; largo--; }  // quita el relleno de signo
        var valor = new byte[largo];
        Array.Copy(b, inicio, valor, 0, largo);
        return valor;
    }

    static byte[] Ajustar(byte[] valor, int largo)
    {
        if (valor.Length == largo) return valor;
        var r = new byte[largo];
        Array.Copy(valor, 0, r, largo - valor.Length, valor.Length);
        return r;
    }
}
'@

$cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(, [Pkcs1]::DesdePem($CertificadoPem))

# Llave persistida en el almacén de la máquina para que IIS (HTTP.sys) la use
$csp = New-Object System.Security.Cryptography.CspParameters(24, 'Microsoft Enhanced RSA and AES Cryptographic Provider', 'erp01-https')
$csp.Flags = [System.Security.Cryptography.CspProviderFlags]::UseMachineKeyStore
$csp.KeyNumber = 1 # AT_KEYEXCHANGE
$rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider($csp)
$rsa.PersistKeyInCsp = $true
$rsa.ImportParameters([Pkcs1]::LeerLlave([Pkcs1]::DesdePem($LlavePem)))
$cert.PrivateKey = $rsa

$almacen = New-Object System.Security.Cryptography.X509Certificates.X509Store('My', 'LocalMachine')
$almacen.Open('ReadWrite')
$almacen.Add($cert)
$almacen.Close()

# ---------- Enlace HTTPS en el sitio predeterminado ----------
Import-Module WebAdministration
if (-not (Get-WebBinding -Name 'Default Web Site' -Protocol https -Port 443)) {
  New-WebBinding -Name 'Default Web Site' -Protocol https -Port 443
}
netsh http delete sslcert ipport=0.0.0.0:443 | Out-Null
netsh http add sslcert ipport=0.0.0.0:443 certhash=$($cert.Thumbprint) appid='{4dc3e181-e14b-4a21-b022-59fc669b0914}' certstorename=MY
Enable-NetFirewallRule -Name 'IIS-WebServerRole-HTTPS-In-TCP'

# Permite ping de entrada para las pruebas de conectividad (V2, V6)
if (-not (Get-NetFirewallRule -DisplayName "Permitir ICMPv4 de entrada" -ErrorAction SilentlyContinue)) {
  New-NetFirewallRule -DisplayName "Permitir ICMPv4 de entrada" -Protocol ICMPv4 -IcmpType 8 -Direction Inbound -Action Allow
}

# Requisito del conector de red privada de Entra (App Proxy) en Windows Server 2019+
$winHttp = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp'
if (-not (Test-Path $winHttp)) { New-Item -Path $winHttp -Force | Out-Null }
Set-ItemProperty -Path $winHttp -Name 'EnableDefaultHTTP2' -Value 0 -Type DWord
