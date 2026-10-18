# Guía de ejecución del plan de validación (V1–V11)

Procedimientos para ejecutar en el prototipo de factibilidad las pruebas del plan de validación del diseño. Cada prueba indica sus requisitos previos, los pasos, el criterio de aceptación y la evidencia que se debe conservar.

> Las capturas y salidas se guardan en `evidencias/V#/` con fecha y hora en el nombre (por ejemplo, `V6_2026-10-20_1532_admin01_nc.png`). No incluir contraseñas ni la PSK en las capturas.

---

## 0. Preparación común

### 0.1 Sesión de pruebas con el perímetro activo

Las pruebas V2, V6, V7, V8 y V11, y parte de V3 y V9, necesitan el perímetro desplegado (≈ USD 2.40/h; el VPN Gateway tarda 30–45 min).

```bash
terraform apply -var perimetro_activo=true      # inicio de la sesión
# ... pruebas ...
terraform apply -var perimetro_activo=false     # cierre de la sesión
```

Agrupar en una misma sesión las pruebas que requieren el perímetro.

### 0.2 Acceso a los equipos por SSH

Solo el router de la sede tiene IP pública (y solo acepta SSH desde `ip_admin`). El resto se alcanza en cascada. Agregar a `~/.ssh/config` (sustituir `<IP_ROUTER>` por `terraform output -raw ip_publica_router_sede`):

```
Host lab-gw
  HostName <IP_ROUTER>
  User azureadmin
  IdentityFile ~/.ssh/lab_azure

Host lab-admin01
  HostName 192.168.10.10
  User azureadmin
  IdentityFile ~/.ssh/lab_azure
  ProxyJump lab-gw

Host lab-srv01
  HostName 192.168.30.10
  User azureadmin
  IdentityFile ~/.ssh/lab_azure
  ProxyJump lab-gw

# Requieren el túnel VPN (perímetro activo)
Host lab-jump01
  HostName 10.20.3.10
  User azureadmin
  IdentityFile ~/.ssh/lab_azure
  ProxyJump lab-gw

Host lab-web01
  HostName 10.20.1.10
  User azureadmin
  IdentityFile ~/.ssh/lab_azure
  ProxyJump lab-jump01
```

Escritorio remoto a vm-erp01 (vía jump01) y luego conectar el cliente RDP a `localhost:13389`:

```bash
ssh -N -L 13389:10.20.1.20:3389 lab-jump01
```

Comandos en las VMs sin conexión directa (funciona aun con el perímetro apagado):

```bash
az vm run-command invoke -g rg-proto-core -n vm-erp01 \
  --command-id RunPowerShellScript --scripts "<comando>"
```

### 0.3 Certificado de la CA interna en los equipos de prueba

```bash
terraform output -raw ca_interna_pem > ca.pem
scp ca.pem lab-admin01:~/ && scp ca.pem lab-srv01:~/
```

### 0.4 Datos que se usan en varias pruebas

```bash
terraform output                       # resumen
terraform output -raw sql_servidor_fqdn
terraform output -raw sql_ip_privada
terraform output usuarios_prueba
terraform output cuentas_emergencia
```

Contraseñas de los usuarios de prueba: Key Vault → `entra-<usuario>`. Copiarlas al portapapeles sin mostrarlas en pantalla:

```bash
az keyvault secret show --vault-name $(terraform output -raw key_vault_nombre) \
  -n entra-finanzas01 --query value -o tsv | wl-copy     # o xclip -selection clipboard
```

### 0.5 Advertencia sobre la ubicación (CA04)

Las VMs del laboratorio salen a Internet desde IPs de Azure en Estados Unidos. Con **CA04 activa**, cualquier inicio de sesión de Entra hecho **desde una VM** (por ejemplo, el registro del conector de App Proxy en vm-erp01) se bloquea. Hacer esos pasos con las políticas en modo solo informe, o con una cuenta de emergencia.

### 0.6 Configuración previa a las pruebas de identidad

1. Aplicar la capa de identidad con `estado_acceso_condicional = "enabledForReportingButNotEnforced"`.
2. Completar los pasos manuales de la sección 10 de `inventario.md`.
3. Revisar en **Entra → Acceso condicional → Información y notificaciones** que las políticas en solo informe se comportan como se espera.
4. Activar las políticas: `estado_acceso_condicional = "enabled"` en `terraform.tfvars` y `terraform apply`.

---

## V1 — Revisión del diseño

**Requisitos:** documento de diseño, `docs/inventario.md`, salida de `terraform plan`.

**Pasos**
1. Preparar la lista de verificación de requisitos con una fila por control del diseño (identidad, red, datos, monitoreo, continuidad) y la referencia al recurso del laboratorio que lo implementa (sección del inventario).
2. Generar la evidencia técnica de la configuración desplegada:
   ```bash
   terraform plan -no-color > evidencias/V1/plan.txt       # debe indicar "No changes"
   terraform state list > evidencias/V1/recursos.txt
   ```
3. Revisar el diseño con la Dirección de TI, el equipo de seguridad y el de infraestructura; registrar las observaciones con su criticidad.
4. Atender las observaciones críticas (cambio en el código → commit → `apply`) y registrar el commit que resuelve cada una.
5. Aprobar el acta.

**Criterio:** todas las observaciones críticas atendidas y acta aprobada.
**Evidencia:** acta de revisión firmada, lista de verificación, `plan.txt`.

---

## V2 — Conectividad híbrida

**Requisitos:** perímetro activo; `ca.pem` en vm-srv01.

**Pasos**
1. **Estado del túnel en Azure** (debe devolver `Connected`):
   ```bash
   az network vpn-connection show -g rg-proto-perimetro -n con-proto-sede \
     --query connectionStatus -o tsv
   ```
   Captura del portal: *Conexiones → con-proto-sede → Información general*.
2. **Estado del túnel en la sede:**
   ```bash
   ssh lab-gw 'sudo swanctl --list-sas'
   ```
   Debe mostrar la IKE SA `azure` en `ESTABLISHED` y la CHILD SA `redes-azure` en `INSTALLED` con los selectores 192.168.0.0/16 === 10.10.0.0/16 10.20.0.0/16.
3. **Acceso de la VLAN de servidores a la zona de aplicaciones:**
   ```bash
   ssh lab-srv01
   curl --cacert ca.pem https://web01.interno.lab -o /dev/null -w '%{http_code}\n'    # 200
   ```
4. **Solo responden los puertos autorizados:**
   ```bash
   nmap -Pn -p 22,80,443,1433,3389 10.20.1.10 10.20.1.20 10.20.3.10 <IP_PRIVADA_SQL>
   ```
   Resultado esperado: 443 abierto en .1.10 y .1.20; 22 abierto en 10.20.3.10 (el Firewall también permite 3389, pero jump01 es Linux y no escucha en ese puerto); el resto `filtered`.
   Azure Firewall completa el *handshake* TCP en 80 y 443 por su proxy de reglas de aplicación, por lo que `nmap` puede mostrarlos `open` aunque no haya regla. Confirmar a nivel HTTP: una respuesta `HTTP 470` con `Action: Deny. Reason: No rule matched` indica bloqueo:
   ```bash
   curl -sk -o /dev/null -w '%{http_code}\n' http://10.20.3.10/     # 470
   ```
5. **Caída de una instancia de la puerta de enlace.** El VPN Gateway activo-en espera tiene dos instancias; el *reset* reinicia la activa y fuerza la conmutación a la de reserva.
   - Terminal 1 (vm-srv01), monitoreo continuo:
     ```bash
     while true; do echo "$(date +%T) $(curl -s -o /dev/null -w '%{http_code}' --max-time 2 --cacert ca.pem https://web01.interno.lab)"; sleep 1; done | tee v2-conmutacion.log
     ```
   - Terminal 2 (vm-gw-sede): `sudo journalctl -fu strongswan`
   - Terminal 3 (local):
     ```bash
     date +%T; az network vnet-gateway reset -g rg-proto-core -n vgw-proto; date +%T
     ```
   - Registrar la hora del primer error, la de la reconexión de strongSwan y la de la primera respuesta 200. Confirmar de nuevo `swanctl --list-sas`.
6. **Registros del Firewall** (Log Analytics):
   ```kusto
   AZFWNetworkRule
   | where TimeGenerated > ago(1h) and SourceIp startswith "192.168."
   | project TimeGenerated, SourceIp, DestinationIp, DestinationPort, Action, Rule
   | order by TimeGenerated desc
   ```

**Criterio:** túnel activo; solo responden los puertos autorizados; reconexión automática tras la conmutación (sin intervención manual).
**Evidencia:** estado de la conexión (CLI y portal), `swanctl --list-sas`, salida de `nmap`, `v2-conmutacion.log` con el tiempo de corte, consulta de AZFWNetworkRule.

---

## V3 — Acceso permitido y denegado

**Requisitos:** P2 activo; políticas de acceso condicional **activadas**; ERP publicado con App Proxy y asignado a grp-finanzas y grp-comercial-remoto; MFA registrado en los usuarios de prueba (passkey en adminti01).

**Cómo variar cada dimensión**
- **Ubicación fuera de El Salvador:** navegar a través de la sede, que sale a Internet desde Estados Unidos:
  ```bash
  ssh -N -D 1080 lab-gw
  ```
  y configurar el navegador con el proxy SOCKS5 `localhost:1080` (o usar un perfil separado).
- **Dispositivo:** Windows (o Android/iOS) frente a Linux (plataforma no aprobada).
- **Sesiones limpias:** ventana privada nueva para cada caso.

**Matriz de casos** (acceso a la URL externa del ERP publicada en App Proxy y a `https://myapps.microsoft.com`)

| # | Usuario | Ubicación | Dispositivo | Resultado esperado | Control |
|---|---|---|---|---|---|
| 1 | finanzas01 | SV | Windows | Permitido tras MFA | CA01 |
| 2 | operativo01 | SV | Windows | Denegado en el ERP (no asignado) | Asignación de la aplicación |
| 3 | comercial01 | SV | Windows | Permitido tras MFA | CA01 |
| 4 | comercial01 | SV | Linux | Bloqueado | CA06 |
| 5 | comercial01 | Fuera de SV (SOCKS) | Windows | Bloqueado | CA04 |
| 6 | adminti01 | SV | Cualquiera, MFA con Authenticator | Bloqueado (exige método resistente a phishing) | CA03 |
| 7 | adminti01 | SV | Cualquiera, passkey | Permitido | CA03 |
| 8 | emergencia01 | Fuera de SV | Cualquiera | Permitido (excluida); genera alerta en Sentinel | Exclusión + regla analítica |
| 9 | finanzas01 | SV | Cliente heredado | Bloqueado | CA02 (verificar con la herramienta **What If**) |

**Pasos**
1. Ejecutar cada caso y anotar en la matriz la hora y el resultado observado.
2. Para CA02, usar *Acceso condicional → What If* con finanzas01, aplicación "Office 365 Exchange Online" y cliente "Exchange ActiveSync / Otros clientes" (el inquilino no tiene buzones para probarlo en vivo).
3. Consultar los registros:
   ```kusto
   SigninLogs
   | where TimeGenerated > ago(4h)
   | where UserPrincipalName has_any ("finanzas01","operativo01","comercial01","adminti01","emergencia01")
   | extend Politicas = ConditionalAccessPolicies
   | project TimeGenerated, UserPrincipalName, AppDisplayName, IPAddress, Location,
             Plataforma = tostring(DeviceDetail.operatingSystem), ResultType, ResultDescription,
             ConditionalAccessStatus, Politicas
   | order by TimeGenerated asc
   ```
4. Comparar el resultado obtenido con el esperado en cada fila.

**Criterio:** 100 % de los casos con el resultado esperado.
**Evidencia:** matriz completa, capturas de cada pantalla de resultado, consulta de SigninLogs (y la pestaña "Acceso condicional" del detalle de cada inicio de sesión), resultado de What If.

---

## V4 — MFA

**Requisitos:** métodos de autenticación configurados (SMS y voz desactivados; Authenticator y FIDO2/passkey activados); CA01 activa.

**Pasos**
1. **Sin segundo factor:** iniciar sesión como finanzas01 con la contraseña correcta y cancelar o dejar expirar la solicitud de MFA. Resultado esperado: acceso no concedido.
2. **Método no permitido:** con comercial02 (sin métodos registrados), abrir `https://aka.ms/mysecurityinfo` → *Agregar método*. Verificar que **no** aparecen "Teléfono" ni "SMS". Captura de la lista.
3. **Método aprobado:** completar el inicio de sesión con Microsoft Authenticator (finanzas01) y con passkey (adminti01).
4. Registros:
   ```kusto
   SigninLogs
   | where TimeGenerated > ago(2h) and UserPrincipalName has_any ("finanzas01","comercial02","adminti01")
   | mv-expand Detalle = AuthenticationDetails
   | project TimeGenerated, UserPrincipalName, ResultType, ResultDescription,
             Metodo = tostring(Detalle.authenticationMethod),
             Exito = tostring(Detalle.succeeded),
             Requisito = AuthenticationRequirement
   ```
   Los intentos del paso 1 aparecen con `ResultType` distinto de 0 (por ejemplo 500121, autenticación fuerte no completada).
5. Captura de *Entra → Métodos de autenticación → Directivas* con la configuración vigente.

**Criterio:** acceso bloqueado sin MFA; solo se aceptan los métodos aprobados.
**Evidencia:** registros de inicio de sesión con el detalle de autenticación, captura de los métodos disponibles y de la directiva.

---

## V5 — PIM

**Requisitos:** capa de identidad aplicada; política de User Administrator configurada en el portal (máximo 4 h, justificación, sin aprobación); adminti01 con passkey registrada (CA03).

**Pasos**

*A. Rol con aprobación (Contributor sobre rg-proto-core)*
1. Antes de activar, como adminti01, verificar que no tiene permisos:
   ```bash
   az login   # como adminti01
   az group update -n rg-proto-core --set tags.prueba=v5     # AuthorizationFailed
   ```
2. En el portal, como adminti01: *PIM → Mis roles → Recursos de Azure → Contributor (rg-proto-core) → Activar*. Comprobar que la duración máxima ofrecida es **4 h**; escribir una justificación; enviar.
3. Volver a ejecutar el comando del paso 1 **antes** de la aprobación: debe seguir fallando.
4. Como aprobador (integrante del equipo configurado): *PIM → Aprobar solicitudes → Aprobar* con justificación.
5. Repetir el comando: ahora debe funcionar. Revertir con `az group update -n rg-proto-core --remove tags.prueba`.

*B. Rol sin aprobación (User Administrator de Entra)*
6. Como adminti01: *PIM → Mis roles → Roles de Microsoft Entra → User Administrator → Activar* (4 h, justificación). Se activa sin aprobación.
7. Verificar el privilegio: restablecer la contraseña de comercial02 (permitido durante la ventana).

*C. Expiración*
8. Registrar la hora de fin de cada activación (*PIM → Mis roles → Asignaciones activas*).
9. Pasadas las 4 h (o tras *Desactivar*), repetir los pasos 1 y 7: ambos deben fallar.
10. Registros:
    ```kusto
    AuditLogs
    | where TimeGenerated > ago(1d) and LoggedByService == "PIM"
    | project TimeGenerated, OperationName, Result,
              Iniciador = tostring(InitiatedBy.user.userPrincipalName),
              Objetivo = tostring(TargetResources[0].displayName),
              Justificacion = tostring(AdditionalDetails)
    | order by TimeGenerated asc
    ```

**Criterio:** ningún privilegio fuera de la ventana de activación; duración máxima de 4 h.
**Evidencia:** historial de auditoría de PIM (*PIM → Historial de auditoría de recursos/roles*), salidas de los comandos antes, durante y después de la ventana, consulta de AuditLogs.

---

## V6 — Segmentación

**Requisitos:** perímetro activo; identidad de vm-erp01 creada como usuario de la base de datos (opcional, para el paso 4).

**Pasos**
1. **Desde la VLAN administrativa** (debe fallar):
   ```bash
   ssh lab-admin01
   nslookup <sql_servidor_fqdn>                 # resuelve a la IP privada 10.20.2.x
   nc -zv -w 5 <sql_servidor_fqdn> 1433         # timeout
   ```
2. **Desde la zona de aplicaciones** (debe funcionar):
   ```bash
   az vm run-command invoke -g rg-proto-core -n vm-erp01 --command-id RunPowerShellScript \
     --scripts "Test-NetConnection <sql_servidor_fqdn> -Port 1433 | Select-Object ComputerName,RemoteAddress,TcpTestSucceeded"
   ```
   Resultado esperado: `TcpTestSucceeded : True`.
3. **Registros del Firewall** (los dos casos pasan por él):
   ```kusto
   AZFWNetworkRule
   | where TimeGenerated > ago(1h) and DestinationPort == 1433
   | project TimeGenerated, SourceIp, DestinationIp, DestinationPort, Action, Rule
   | order by TimeGenerated asc
   ```
   Resultado esperado: 192.168.10.10 → `Deny`; 10.20.1.20 → `Allow` (regla `apps-a-datos-sql`).
4. *(Opcional)* Conexión real con la identidad administrada de vm-erp01 (token de IMDS + SqlClient):
   ```powershell
   $t = (Invoke-RestMethod -Headers @{Metadata="true"} -Uri "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://database.windows.net/").access_token
   $c = New-Object System.Data.SqlClient.SqlConnection("Server=tcp:<sql_servidor_fqdn>,1433;Database=sqldb-erp;Encrypt=True;")
   $c.AccessToken = $t; $c.Open(); $c.State; $c.Close()
   ```

**Criterio:** bloqueo desde la VLAN administrativa; acceso permitido solo desde la zona de aplicaciones.
**Evidencia:** salidas de `nc` y `Test-NetConnection`, consulta de AZFWNetworkRule con ambos casos.

---

## V7 — Reglas del WAF

**Requisitos:** perímetro activo.

**Pasos**
1. Variables:
   ```bash
   IP=$(terraform output -raw ip_publica_appgw)
   ```
2. **Tráfico legítimo** (esperado 200):
   ```bash
   curl -sk -o /dev/null -w '%{http_code}\n' https://$IP/
   curl -sk -o /dev/null -w '%{http_code}\n' -G https://$IP/rest/products/search --data-urlencode "q=apple"
   ```
3. **Inyección SQL** (esperado 403):
   ```bash
   curl -sk -o /dev/null -w '%{http_code}\n' -G https://$IP/rest/products/search --data-urlencode "q=')) OR 1=1--"
   curl -sk -o /dev/null -w '%{http_code}\n' -X POST https://$IP/rest/user/login \
     -H 'Content-Type: application/json' -d "{\"email\":\"' OR 1=1--\",\"password\":\"x\"}"
   ```
4. **XSS** (esperado 403):
   ```bash
   curl -sk -o /dev/null -w '%{http_code}\n' -G https://$IP/rest/products/search --data-urlencode "q=<script>alert(1)</script>"
   curl -sk -o /dev/null -w '%{http_code}\n' -G https://$IP/ --data-urlencode "x=<img src=x onerror=alert(1)>"
   ```
5. **Navegación funcional:** abrir `https://<IP>` en el navegador, registrar un usuario, iniciar sesión, buscar productos y agregar al carrito. Anotar cualquier función que falle.
6. **Falsos positivos:**
   ```kusto
   AGWFirewallLogs
   | where TimeGenerated > ago(1h) and Action in ("Blocked", "Matched")
   | project TimeGenerated, ClientIp, RequestUri, RuleId, RuleGroup = tostring(split(RuleId, "-")[0]), Message, Action
   | order by TimeGenerated asc
   ```
   Para cada bloqueo de tráfico legítimo: documentar la regla y la solicitud, y ajustarla en `terraform.tfvars`, por ejemplo:
   ```hcl
   waf_exclusiones = [
     { variable = "RequestCookieNames", operador = "Equals", selector = "token" }
   ]
   waf_reglas_deshabilitadas = {
     "SQLI" = ["942430"]
   }
   ```
   Aplicar, repetir la navegación y confirmar que las cargas de los pasos 3 y 4 siguen bloqueadas.

**Criterio:** cargas maliciosas bloqueadas (HTTP 403); tráfico legítimo atendido; falsos positivos documentados y ajustados.
**Evidencia:** salidas de `curl`, consulta de AGWFirewallLogs, tabla de falsos positivos con la regla, el ajuste y el commit correspondiente.

---

## V8 — IDPS

**Requisitos:** perímetro activo. Según la guía de Microsoft para Azure Firewall Premium, la firma se prueba con tráfico **HTTP** (sin inspección TLS, el IDPS no ve el contenido de HTTPS).

**Pasos**
1. Desde un equipo del spoke (su salida a Internet pasa por el Firewall):
   ```bash
   ssh lab-jump01
   curl -A "HaxerMen" -v --max-time 10 http://azure.archive.ubuntu.com/
   ```
   Resultado esperado: conexión restablecida o sin respuesta (denegada por el IDPS).
2. Control: la misma solicitud sin el agente de usuario malicioso debe responder.
   ```bash
   curl -s -o /dev/null -w '%{http_code}\n' http://azure.archive.ubuntu.com/
   ```
3. Registros (pueden tardar 5–10 min):
   ```kusto
   AZFWIdpsSignature
   | where TimeGenerated > ago(1h)
   | project TimeGenerated, SourceIp, DestinationIp, DestinationPort, SignatureId, Description, Action, Severity
   ```
   Resultado esperado: `SignatureId == 2032081` con `Action` igual a `Deny` o `drop`. El registro muestra como `SourceIp` la IP de la instancia del Firewall en `AzureFirewallSubnet` (10.10.0.x, tras la SNAT hacia Internet), no la de jump01; la correlación se hace por la hora de la prueba.
4. Verificar en Sentinel el incidente de la regla **Firma de IDPS detectada en Azure Firewall**.

**Criterio:** alerta y bloqueo registrados.
**Evidencia:** salida de `curl`, registros de AZFWIdpsSignature, incidente en Sentinel.

---

## V9 — Envío de eventos al SIEM

**Requisitos:** Sentinel activo; perímetro activo durante la generación de datos (para Firewall y App Gateway); P2 activo.

**Pasos**

*A. Recepción de datos de cada fuente*
1. Generar actividad en cada fuente durante la sesión: inicios de sesión en Entra (V3/V4), SSH a las VMs Linux, RDP a vm-erp01, lectura de un secreto de Key Vault, conexión a SQL (V6), tráfico por el Firewall (V2, V6, V8) y por el WAF (V7).
2. Pasadas unas horas, ejecutar la consulta guardada **V9 - Fuentes con datos en las últimas 24 h** (*Log Analytics → Consultas → Validacion*).
3. Comparar con la lista esperada: SigninLogs, AuditLogs, AzureActivity, AzureDiagnostics/AuditEvent (Key Vault), AzureDiagnostics/SQLSecurityAuditEvents, Syslog, SecurityEvent, Heartbeat, AZFWNetworkRule, AZFWApplicationRule, AZFWIdpsSignature, AGWAccessLogs y AGWFirewallLogs.

*B. Regla analítica de prueba asociada al playbook (fuerza bruta)*
4. Registrar la hora de inicio. En una ventana privada, desde El Salvador, intentar 6 veces el inicio de sesión de finanzas01 con una contraseña incorrecta (menos de 10 intentos, para no activar el bloqueo inteligente). Si Entra ya bloqueó la cuenta, o la IP de origen tiene mala reputación (por ejemplo, IPs compartidas de proveedores satelitales), los intentos se registran como 50053 en lugar de 50126; la regla cuenta ambos códigos.
5. Esperar el incidente **Fuerza bruta contra cuentas de Entra ID** (*Sentinel → Incidentes*). Registrar su hora de creación.
6. Verificar la ejecución del playbook: *Logic Apps → pb-proto-deshabilitar-usuario → Historial de ejecuciones*. Registrar la hora de inicio y de fin, y el comentario agregado al incidente.
7. Confirmar el efecto:
   ```bash
   az ad user show --id finanzas01@<dominio> --query accountEnabled    # false
   ```
8. Medición:
   ```kusto
   SecurityIncident
   | where TimeGenerated > ago(2h) and Title has "Fuerza bruta"
   | project IncidentNumber, CreatedTime, Status, Title
   ```
   Tiempo de respuesta = inicio de la ejecución del playbook − creación del incidente (≤ 5 min).
9. Restablecer la cuenta:
   ```bash
   az ad user update --id finanzas01@<dominio> --account-enabled true
   ```
10. *(Complementario)* Iniciar sesión con emergencia01 y verificar el incidente de alta severidad **Inicio de sesión con cuenta de emergencia** (genera incidente pero no ejecuta el playbook, para no deshabilitar el acceso de emergencia).

**Criterio:** todas las fuentes con datos en las últimas 24 h; incidente creado y playbook ejecutado en 5 min o menos.
**Evidencia:** resultado de la consulta guardada, incidente, historial del playbook con tiempos, estado de la cuenta antes y después.

---

## V10 — Respaldo y restauración

**Requisitos:** al menos un punto de recuperación de vm-erp01; cuota de vCPU en eastus para una VM adicional de 1 vCPU (`Standard_F1as_v7`; con 3 de 4 vCPU en uso, la cuota alcanza). Objetivos: ERP con RTO 4 h y RPO 4 h; base de datos con RTO 2 h y RPO 15 min.

**Pasos**

*A. Máquina virtual del ERP*
1. Si aún no hay puntos de recuperación, forzar un respaldo:
   ```bash
   az backup protection backup-now -g rg-proto-core -v $(terraform output -raw boveda_respaldo) \
     --container-name "iaasvmcontainerv2;rg-proto-core;vm-erp01" --item-name vm-erp01 \
     --backup-management-type AzureIaasVM --retain-until <dd-mm-aaaa>
   ```
2. Listar los puntos de recuperación y elegir el más reciente (su antigüedad respecto al "incidente" simulado es el RPO real, que debe ser ≤ 4 h):
   ```bash
   az backup recoverypoint list -g rg-proto-core -v <boveda> \
     --container-name "iaasvmcontainerv2;rg-proto-core;vm-erp01" --item-name vm-erp01 \
     --backup-management-type AzureIaasVM -o table
   ```
3. **T0:** registrar la hora de inicio. En el portal: *Bóveda → Elementos de copia de seguridad → vm-erp01 → Restaurar VM → Crear nueva*, con nombre `vm-erp01-rest`, red `vnet-proto-aislada` / `snet-restauracion` y ubicación de transición `stprotorest<sufijo>`.
4. Al terminar el trabajo de restauración, verificar el servicio:
   ```bash
   az vm run-command invoke -g rg-proto-core -n vm-erp01-rest --command-id RunPowerShellScript \
     --scripts "(Invoke-WebRequest http://localhost -UseBasicParsing).Content"
   ```
   **T1:** hora en que el ERP responde. RTO = T1 − T0 (≤ 4 h).
5. Eliminar la VM restaurada y sus discos al terminar.

*B. Base de datos (restauración a un punto en el tiempo)*
6. Abrir un túnel hacia SQL a través de jump01 (perímetro activo) y conectarse desde el equipo local, para que el inicio de sesión de Entra se origine en El Salvador (CA04):
   ```bash
   echo "127.0.0.1 <sql_servidor_fqdn>" | sudo tee -a /etc/hosts     # el certificado TLS exige el nombre real
   ssh -N -L 1433:<IP_PRIVADA_SQL>:1433 lab-jump01 &
   sqlcmd -S <sql_servidor_fqdn> -d sqldb-erp --authentication-method ActiveDirectoryInteractive
   ```
   El mismo procedimiento sirve para el paso manual `CREATE USER [vm-erp01] FROM EXTERNAL PROVIDER`. Crear un marcador:
   ```sql
   CREATE TABLE dbo.marcador_v10 (id INT IDENTITY, momento DATETIME2 DEFAULT SYSUTCDATETIME());
   INSERT INTO dbo.marcador_v10 DEFAULT VALUES;
   SELECT * FROM dbo.marcador_v10;
   ```
   Esperar 15 min e insertar una segunda fila; anotar la hora UTC entre ambas inserciones (`<T_RESTAURACION>`).
7. **T0:** restaurar a ese momento como base nueva (entorno aislado: no la usa ninguna aplicación):
   ```bash
   az sql db restore -g rg-proto-core -s <servidor> -n sqldb-erp \
     --dest-name sqldb-erp-restaurada --time "<T_RESTAURACION>"
   ```
8. **T1:** al terminar, consultar `dbo.marcador_v10` en `sqldb-erp-restaurada` (`sqlcmd ... -d sqldb-erp-restaurada`): debe existir solo la primera fila. RTO = T1 − T0 (≤ 2 h); la pérdida de datos queda acotada al punto elegido (RPO ≤ 15 min).
9. Eliminar la base restaurada y quitar la línea agregada a `/etc/hosts`:
   ```bash
   az sql db delete -g rg-proto-core -s <servidor> -n sqldb-erp-restaurada --yes
   ```

**Criterio:** restauración dentro del RTO y RPO definidos.
**Evidencia:** informe de restauración con T0, T1, punto de recuperación usado, RPO y RTO obtenidos frente a los objetivos; capturas de los trabajos de restauración y de la verificación.

---

## V11 — Reversión

**Requisitos:** perímetro activo (para comparar con el servicio en la nube); `ca.pem` en vm-admin01. Objetivo: servicio local operativo en 4 h o menos.

**Pasos**
1. **Estado inicial** desde vm-admin01:
   ```bash
   ssh lab-admin01
   dig +short app.interno.lab                                   # 10.20.1.10
   curl -s --cacert ca.pem https://app.interno.lab | grep -o '<title>.*</title>'   # Juice Shop
   ```
2. Dejar un monitoreo continuo en vm-admin01:
   ```bash
   while true; do echo "$(date +%T) $(dig +short app.interno.lab) $(curl -s --max-time 3 --cacert ca.pem https://app.interno.lab | grep -o '<title>.*</title>')"; sleep 10; done | tee v11-reversion.log
   ```
3. **T0:** declarar la reversión y registrarla en la bitácora.
4. Ejecutar el plan de vuelta atrás:
   ```bash
   terraform apply -var perimetro_activo=true -var servicio_app_activo=local
   ```
   El plan debe mostrar un solo cambio: el registro `app` de `interno.lab`.
5. **T1:** primera línea del monitoreo con `192.168.30.10` y el título "Servicio local". Tiempo de reversión = T1 − T0.
6. Verificar el servicio local de forma funcional (página completa, certificado válido):
   ```bash
   curl -v --cacert ca.pem https://app.interno.lab 2>&1 | grep -E 'subject:|SSL connection|<h1>'
   ```
7. Volver a la nube: `terraform apply -var perimetro_activo=true -var servicio_app_activo=nube` y confirmar en el monitoreo.

**Bitácora**

| Hora | Actividad | Responsable | Resultado |
|---|---|---|---|
| T0 | Decisión de reversión | | |
| | Inicio del cambio de DNS (`terraform apply`) | | |
| | Fin del `apply` | | |
| T1 | Primer acceso exitoso al servicio local | | |
| | Verificación funcional | | |
| | Retorno al servicio en la nube | | |

**Criterio:** servicio local operativo en 4 h o menos.
**Evidencia:** bitácora completa, `v11-reversion.log`, salida del `terraform apply`.

---

## Resumen de requisitos por prueba

| Prueba | Perímetro | Identidad (P2 + CA) | Sentinel | Pasos manuales previos |
|---|---|---|---|---|
| V1 | — | — | — | Lista de verificación |
| V2 | Sí | — | Sí (registros) | — |
| V3 | No (si está activo, el conector sale por el Firewall, que ya lo permite) | Sí, activadas | Sí | App Proxy, conector, MFA de los usuarios |
| V4 | — | Sí | Sí | Métodos de autenticación |
| V5 | — | Sí | — | Política de User Administrator, passkey de adminti01 |
| V6 | Sí | — | Sí | — |
| V7 | Sí | — | Sí | — |
| V8 | Sí | — | Sí | — |
| V9 | Sí (generación de datos) | Sí | Sí | — |
| V10 | No | — | — | Cuota de vCPU |
| V11 | Sí | — | — | — |
