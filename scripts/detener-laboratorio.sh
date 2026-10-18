#!/usr/bin/env bash
# Detiene los servicios del laboratorio para controlar el costo.
#
# Uso:
#   scripts/detener-laboratorio.sh estado     Muestra lo que está generando costo
#   scripts/detener-laboratorio.sh pausar     Destruye el perímetro y desasigna las VMs (se conserva todo lo demás)
#   scripts/detener-laboratorio.sh destruir   Elimina todo el laboratorio (terraform destroy) y los respaldos residuales
#
# Requiere: az (con sesión iniciada), terraform y python3. Se ejecuta desde cualquier ubicación.

set -euo pipefail

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RG_CORE="rg-proto-core"
RG_PERIMETRO="rg-proto-perimetro"
RG_SEDE="rg-proto-sede"
UBICACION_SQL="centralus"

tf() { terraform -chdir="$RAIZ" "$@"; }
titulo() { printf '\n== %s\n' "$1"; }
existe_grupo() { [ "$(az group exists -n "$1")" = "true" ]; }

# ---------- Consultas ----------
vms_encendidas() {
  local rg
  for rg in "$RG_CORE" "$RG_SEDE"; do
    existe_grupo "$rg" || continue
    az vm list -d -g "$rg" --query "[?powerState!='VM deallocated'].id" -o tsv
  done
}

recursos_perimetro() {
  {
    existe_grupo "$RG_CORE" && az resource list -g "$RG_CORE" \
      --query "[?type=='Microsoft.Network/azureFirewalls' || type=='Microsoft.Network/virtualNetworkGateways'].name" -o tsv
    existe_grupo "$RG_PERIMETRO" && az resource list -g "$RG_PERIMETRO" \
      --query "[?type=='Microsoft.Network/applicationGateways'].name" -o tsv
  } || true
}

mostrar_estado() {
  titulo "Perímetro (Firewall, VPN Gateway, App Gateway: ≈ USD 2.40/h)"
  local perimetro
  perimetro="$(recursos_perimetro)"
  if [ -n "$perimetro" ]; then echo "ACTIVO:"; echo "$perimetro" | sed 's/^/  - /'; else echo "No desplegado"; fi

  titulo "Máquinas virtuales"
  local rg
  for rg in "$RG_CORE" "$RG_SEDE"; do
    existe_grupo "$rg" || continue
    az vm list -d -g "$rg" --query "[].{vm:name, estado:powerState, tamano:hardwareProfile.vmSize}" -o table
  done

  titulo "Recursos que cobran aunque las VMs estén desasignadas"
  if existe_grupo "$RG_CORE"; then
    az sql db list -g "$RG_CORE" --server "$(az sql server list -g "$RG_CORE" --query '[0].name' -o tsv 2>/dev/null)" \
      --query "[?name!='master'].{base:name, nivel:currentServiceObjectiveName}" -o table 2>/dev/null || true
  fi
  local rg2
  for rg2 in "$RG_CORE" "$RG_SEDE" "$RG_PERIMETRO"; do
    existe_grupo "$rg2" || continue
    az network public-ip list -g "$rg2" --query "[].{ip_publica:name, grupo:resourceGroup}" -o table
  done
  echo "Además: discos administrados, Azure Backup y la ingesta de Log Analytics/Sentinel."
}

# ---------- Pausar ----------
pausar() {
  titulo "1/2 Perímetro"
  if [ -n "$(recursos_perimetro)" ]; then
    echo "Se destruirá el perímetro. Revisa el plan antes de confirmar."
    # Aplicación dirigida: solo el perímetro y lo que depende de él, para no
    # crear ni modificar el resto del laboratorio.
    tf apply -var perimetro_activo=false \
      -target=module.perimetro \
      -target=azurerm_monitor_diagnostic_setting.firewall \
      -target=azurerm_monitor_diagnostic_setting.appgw \
      -target=azurerm_virtual_network_peering.cargas_a_hub
  else
    echo "No hay perímetro desplegado."
  fi

  titulo "2/2 Máquinas virtuales"
  local ids
  ids="$(vms_encendidas)"
  if [ -n "$ids" ]; then
    # shellcheck disable=SC2086
    az vm deallocate --ids $ids -o none
    echo "VMs desasignadas."
  else
    echo "No hay VMs encendidas."
  fi

  mostrar_estado
}

# ---------- Destruir ----------
limpiar_respaldos() {
  existe_grupo "$RG_CORE" || return 0
  local boveda
  boveda="$(az backup vault list -g "$RG_CORE" --query '[0].name' -o tsv)"
  [ -n "$boveda" ] || return 0

  echo "Bóveda: $boveda"
  # Sin desactivar la eliminación temporal, la bóveda queda bloqueada 14 días
  az backup vault backup-properties set -g "$RG_CORE" -n "$boveda" \
    --soft-delete-feature-state Disable -o none

  local elementos linea contenedor elemento estado
  elementos="$(az backup item list -g "$RG_CORE" -v "$boveda" --backup-management-type AzureIaasVM \
    --query "[].[properties.containerName, name, properties.isScheduledForDeferredDelete]" -o tsv)"
  while IFS=$'\t' read -r contenedor elemento estado; do
    [ -n "${elemento:-}" ] || continue
    if [ "$estado" = "true" ]; then
      az backup protection undelete -g "$RG_CORE" -v "$boveda" -c "$contenedor" -i "$elemento" \
        --backup-management-type AzureIaasVM --workload-type VM -o none
    fi
    echo "  Eliminando datos de respaldo: $elemento"
    az backup protection disable -g "$RG_CORE" -v "$boveda" -c "$contenedor" -i "$elemento" \
      --backup-management-type AzureIaasVM --workload-type VM --delete-backup-data true --yes -o none
  done <<< "$elementos"
}

limpiar_ltr_sql() {
  # Las copias de retención a largo plazo sobreviven al borrado del servidor y se siguen cobrando
  local copias
  copias="$(az sql db ltr-backup list -l "$UBICACION_SQL" -o json 2>/dev/null || echo '[]')"
  python3 -c '
import json, sys
for c in json.loads(sys.argv[1]):
    if c.get("serverName", "").startswith("sql-proto-"):
        print(c["serverName"], c["databaseName"], c["name"], sep="\t")
' "$copias" | while IFS=$'\t' read -r servidor base nombre; do
    echo "  Eliminando copia LTR: $servidor/$base/$nombre"
    az sql db ltr-backup delete -l "$UBICACION_SQL" -s "$servidor" -d "$base" -n "$nombre" --yes -o none
  done
}

destruir() {
  cat <<'AVISO'
Se eliminará TODO el laboratorio: redes, VMs, SQL, Key Vault, Sentinel, respaldos,
usuarios, grupos y políticas de Entra ID. Se pierden las evidencias que no hayas exportado
(registros de Log Analytics, historial de PIM, puntos de restauración).
No se toca el estado remoto (rg-proto-tfstate).
AVISO
  read -r -p "Escribe DESTRUIR para continuar: " confirmacion
  [ "$confirmacion" = "DESTRUIR" ] || { echo "Cancelado."; exit 1; }

  titulo "1/3 Respaldos de Azure Backup"
  limpiar_respaldos

  titulo "2/3 terraform destroy (revisa el plan antes de confirmar)"
  tf destroy -var perimetro_activo=false

  titulo "3/3 Copias LTR huérfanas de Azure SQL"
  limpiar_ltr_sql

  titulo "Resultado"
  local rg
  for rg in "$RG_CORE" "$RG_PERIMETRO" "$RG_SEDE"; do
    if existe_grupo "$rg"; then echo "Aún existe: $rg"; else echo "Eliminado: $rg"; fi
  done
  echo "Key Vault queda en eliminación temporal 7 días (sin costo)."
  echo "Para eliminar también el estado remoto: az group delete -n rg-proto-tfstate"
}

# ---------- Principal ----------
case "${1:-}" in
  estado)   mostrar_estado ;;
  pausar)   pausar ;;
  destruir) destruir ;;
  *)
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
