#!/usr/bin/env bash
# disk-audit.sh — Análisis de System Data en macOS
# Uso: bash ~/disk-audit.sh

set -euo pipefail

# ── Colores ──────────────────────────────────────────────────────────────────
BOLD=$'\033[1m'
DIM=$'\033[2m'
RED=$'\033[0;31m'
YELLOW=$'\033[0;33m'
GREEN=$'\033[0;32m'
CYAN=$'\033[0;36m'
RESET=$'\033[0m'

# ── Helpers ───────────────────────────────────────────────────────────────────
dir_size() {
  local path="$1"
  [[ ! -e "$path" ]] && echo "-" && return
  du -sh "$path" 2>/dev/null | awk '{print $1}' || echo "?"
}

to_kb() {
  local s="$1"
  local num unit
  num=$(echo "$s" | sed 's/[^0-9.]//g')
  unit=$(echo "$s" | sed 's/[0-9.]//g' | tr -d ' ' | tr '[:lower:]' '[:upper:]')
  case "$unit" in
    T)   awk "BEGIN{printf \"%.0f\", $num * 1024 * 1024 * 1024}" ;;
    G|GB) awk "BEGIN{printf \"%.0f\", $num * 1024 * 1024}" ;;
    M)   awk "BEGIN{printf \"%.0f\", $num * 1024}" ;;
    K|KB) awk "BEGIN{printf \"%.0f\", $num}" ;;
    B)   echo "1" ;;
    *)   echo "0" ;;
  esac
}

rows=()

add_row() {
  local size="$1" label="$2" note="$3"
  [[ "$size" == "-" || "$size" == "0B" || "$size" == "0" ]] && return
  local kb
  kb=$(to_kb "$size")
  [[ "$kb" -eq 0 ]] && return
  rows+=("${kb}|${size}|${label}|${note}")
}

section() {
  echo -e "\n${CYAN}${BOLD}── $1 ──${RESET}"
}

USER_LIB="${HOME}/Library"
SYS_LIB="/Library"

_clean_sim_runtimes() {
  echo "  Eliminando Simulator Runtimes no usados..."
  xcrun simctl runtime delete all 2>&1 | sed 's/^/  /'
}

_clean_caches() {
  local ok=0 fail=0 d
  for d in "${USER_LIB}/Caches/"/*/; do
    [[ -d "$d" ]] || continue
    rm -rf "$d" 2>/dev/null && (( ok++ )) || (( fail++ ))
  done
  echo "  Borrados: $ok  |  Sin permisos/en uso: $fail"
}

run_audit() {
rows=()
actions=()
# ── Header ────────────────────────────────────────────────────────────────────
clear
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║        🔍  macOS Disk Audit — System Data                ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${RESET}"
echo -e "${DIM}  $(date '+%Y-%m-%d %H:%M:%S')  •  $(hostname)  •  macOS $(sw_vers -productVersion)${RESET}"
echo ""
echo -e "${YELLOW}Analizando... esto puede tomar unos segundos.${RESET}"

# ── 1. Xcode ──────────────────────────────────────────────────────────────────
section "Xcode"

add_row "$(dir_size "${USER_LIB}/Developer/Xcode/DerivedData")" \
  "Xcode DerivedData" "Builds intermedios — seguro borrar"

add_row "$(dir_size "${USER_LIB}/Developer/Xcode/Archives")" \
  "Xcode Archives" "Builds archivados para distribución"

for PLATFORM in "iOS" "watchOS" "tvOS" "visionOS" "macOS"; do
  DS="${USER_LIB}/Developer/Xcode/${PLATFORM} DeviceSupport"
  SZ=$(dir_size "$DS")
  [[ "$SZ" == "-" ]] && continue
  COUNT=$(ls "$DS" 2>/dev/null | wc -l | tr -d ' ')
  add_row "$SZ" "Xcode ${PLATFORM} DeviceSupport" "${COUNT} versiones — borra las antiguas"
done

add_row "$(dir_size "${USER_LIB}/Caches/com.apple.dt.Xcode")" \
  "Xcode Caches" "Seguro borrar"

add_row "$(dir_size "${USER_LIB}/Developer/Xcode/UserData/IB Support")" \
  "Xcode IB Support" "Cache de Interface Builder"

# ── 2. iOS Simulator ──────────────────────────────────────────────────────────
section "iOS Simulator"

add_row "$(dir_size "${SYS_LIB}/Developer/CoreSimulator/Caches/dyld")" \
  "CoreSimulator dyld Caches (sistema)" "Borrar: sudo rm -rf /Library/Developer/CoreSimulator/Caches/dyld"

add_row "$(dir_size "${USER_LIB}/Developer/CoreSimulator/Caches/dyld")" \
  "CoreSimulator dyld Caches (usuario)" "Seguro borrar"

if [[ -d "${USER_LIB}/Developer/CoreSimulator/Devices" ]]; then
  COUNT=$(ls "${USER_LIB}/Developer/CoreSimulator/Devices" 2>/dev/null | wc -l | tr -d ' ')
  add_row "$(dir_size "${USER_LIB}/Developer/CoreSimulator/Devices")" \
    "Simuladores iOS" "${COUNT} dispositivos — xcrun simctl delete unavailable"
fi

add_row "$(dir_size "${SYS_LIB}/Developer/CoreSimulator/Profiles/Runtimes")" \
  "Simulator Runtimes" "Borra versiones antiguas en Xcode > Settings > Platforms"

# ── 3. Homebrew ───────────────────────────────────────────────────────────────
section "Homebrew"

add_row "$(dir_size "${HOME}/Library/Caches/Homebrew")" \
  "Homebrew Cache" "Limpiar: brew cleanup --prune=all"

for BREW_PREFIX in "/opt/homebrew" "/usr/local"; do
  if [[ -d "${BREW_PREFIX}/Cellar" ]]; then
    add_row "$(dir_size "${BREW_PREFIX}/Cellar")" \
      "Homebrew Cellar (${BREW_PREFIX})" "Fórmulas instaladas"
    add_row "$(dir_size "${BREW_PREFIX}/Caskroom")" \
      "Homebrew Caskroom (${BREW_PREFIX})" "Casks instalados"
    break
  fi
done

# ── 4. Docker ─────────────────────────────────────────────────────────────────
section "Docker"

add_row "$(dir_size "${USER_LIB}/Containers/com.docker.docker")" \
  "Docker (app container)" "Imágenes y contenedores"

for DOCKER_VM in \
  "${HOME}/.docker/desktop/vms/0/data/Docker.raw" \
  "${USER_LIB}/Containers/com.docker.docker/Data/vms/0/data/Docker.raw" \
  "${HOME}/Library/Group Containers/group.com.docker/Data/vms/0/data/Docker.raw"; do
  if [[ -f "$DOCKER_VM" ]]; then
    SZ=$(du -sh "$DOCKER_VM" 2>/dev/null | awk '{print $1}')
    add_row "$SZ" "Docker VM disk image" "docker system prune -a para reducir"
    break
  fi
done

# ── 5. Máquinas Virtuales ─────────────────────────────────────────────────────
section "Máquinas Virtuales"

add_row "$(dir_size "${USER_LIB}/Containers/com.utmapp.UTM")" \
  "UTM (container)" "VMs de UTM — borra desde la app"

add_row "$(dir_size "${HOME}/Documents/UTM")" \
  "UTM VMs (Documents)" "Archivos .utm"

for PD in "${HOME}/Parallels" "${HOME}/Documents/Parallels"; do
  SZ=$(dir_size "$PD")
  [[ "$SZ" == "-" ]] && continue
  add_row "$SZ" "Parallels VMs" "Archivos .pvm"
done

add_row "$(dir_size "${HOME}/Virtual Machines.localized")" \
  "VMware Fusion VMs" "Archivos .vmwarevm"

add_row "$(dir_size "${HOME}/VirtualBox VMs")" \
  "VirtualBox VMs" "Archivos .vdi"

# ── 6. Node.js / npm / yarn / pnpm ───────────────────────────────────────────
section "Node.js / npm / yarn / pnpm / bun"

add_row "$(dir_size "${HOME}/.npm")" \
  "npm Cache (~/.npm)" "Limpiar: npm cache clean --force"

add_row "$(dir_size "${HOME}/Library/Caches/Yarn")" \
  "Yarn Cache" "Limpiar: yarn cache clean"

add_row "$(dir_size "${HOME}/.yarn/cache")" \
  "Yarn 2+ Cache" "Limpiar: yarn cache clean"

for PNPM_STORE in "${HOME}/Library/pnpm/store" "${HOME}/.pnpm-store" "${HOME}/.local/share/pnpm/store"; do
  [[ -d "$PNPM_STORE" ]] || continue
  add_row "$(dir_size "$PNPM_STORE")" "pnpm Store" "Limpiar: pnpm store prune"
  break
done

add_row "$(dir_size "${HOME}/.bun/install/cache")" \
  "Bun Cache" "Seguro borrar"

# ── 7. Python ─────────────────────────────────────────────────────────────────
section "Python"

add_row "$(dir_size "${HOME}/Library/Caches/pip")" \
  "pip Cache" "Limpiar: pip cache purge"

add_row "$(dir_size "${HOME}/.pyenv/versions")" \
  "pyenv versions" "Borra versiones no usadas"

add_row "$(dir_size "${HOME}/Library/Caches/pypoetry")" \
  "Poetry Cache" "Limpiar: poetry cache clear --all ."

add_row "$(dir_size "${HOME}/.cache/uv")" \
  "uv Cache" "Limpiar: uv cache clean"

# ── 8. Ruby / Gems ────────────────────────────────────────────────────────────
section "Ruby / Gems"

add_row "$(dir_size "${HOME}/.gem")" \
  "Ruby Gems (~/.gem)" "Borra gems no usadas"

add_row "$(dir_size "${HOME}/.bundle")" \
  "Bundler cache" "Limpiar: bundle clean --force"

# ── 9. Rust / Cargo ───────────────────────────────────────────────────────────
section "Rust / Cargo"

add_row "$(dir_size "${HOME}/.cargo/registry")" \
  "Cargo Registry" "Limpiar: cargo cache -a"

add_row "$(dir_size "${HOME}/.cargo/git")" \
  "Cargo Git Sources" "Limpiar: cargo cache -a"

# ── 10. Go ────────────────────────────────────────────────────────────────────
section "Go"

for GOCACHE in "${HOME}/Library/Caches/go-build" "${HOME}/.cache/go-build"; do
  [[ -d "$GOCACHE" ]] || continue
  add_row "$(dir_size "$GOCACHE")" "Go build cache" "Limpiar: go clean -cache"
  break
done

add_row "$(dir_size "${HOME}/go/pkg/mod")" \
  "Go module cache" "Limpiar: go clean -modcache"

# ── 11. Java / Gradle / Maven ─────────────────────────────────────────────────
section "Java / Gradle / Maven"

add_row "$(dir_size "${HOME}/.gradle/caches")" \
  "Gradle Caches" "Borra caches antiguas"

add_row "$(dir_size "${HOME}/.m2/repository")" \
  "Maven Repository" "Borra artefactos no usados"

# ── 12. Unity ─────────────────────────────────────────────────────────────────
section "Unity"

add_row "$(dir_size "${USER_LIB}/Application Support/Unity")" \
  "Unity Hub data" "Proyectos y configuración"

for UNITY_EDITORS in "${USER_LIB}/Unity/Hub/Editor" "/Applications/Unity/Hub/Editor"; do
  [[ -d "$UNITY_EDITORS" ]] || continue
  COUNT=$(ls "$UNITY_EDITORS" 2>/dev/null | wc -l | tr -d ' ')
  add_row "$(dir_size "$UNITY_EDITORS")" "Unity Editors instalados" "${COUNT} versiones"
  break
done

add_row "$(dir_size "${USER_LIB}/Caches/com.unity3d.UnityEditor5.x")" \
  "Unity Editor Cache" "Seguro borrar"

add_row "$(dir_size "${USER_LIB}/Logs/Unity")" \
  "Unity Logs" "Seguro borrar"

# ── 13. App Containers grandes ────────────────────────────────────────────────
section "App Containers (top 10)"

CONTAINERS_DIR="${USER_LIB}/Containers"
if [[ -d "$CONTAINERS_DIR" ]]; then
  while IFS= read -r line; do
    SZ=$(echo "$line" | awk '{print $1}')
    PATH_ITEM=$(echo "$line" | awk '{print $2}')
    APP=$(basename "$PATH_ITEM")
    add_row "$SZ" "Container: ${APP}" ""
  done < <(du -sh "${CONTAINERS_DIR}/"* 2>/dev/null | sort -rh | head -10)
fi

# ── 14. Logs ──────────────────────────────────────────────────────────────────
section "Logs"

add_row "$(dir_size "${USER_LIB}/Logs")" \
  "~/Library/Logs" "Seguro borrar"

add_row "$(dir_size "${USER_LIB}/Logs/DiagnosticReports")" \
  "Crash Reports" "Seguro borrar"

# ── 15. Caches de usuario ─────────────────────────────────────────────────────
section "Caches del sistema"

add_row "$(dir_size "${USER_LIB}/Caches")" \
  "~/Library/Caches (total)" "Mayormente seguro borrar"

if [[ -d "${USER_LIB}/Caches" ]]; then
  while IFS= read -r line; do
    SZ=$(echo "$line" | awk '{print $1}')
    PATH_ITEM=$(echo "$line" | awk '{print $2}')
    APP=$(basename "$PATH_ITEM")
    [[ "$PATH_ITEM" == "${USER_LIB}/Caches" ]] && continue
    add_row "$SZ" "Cache: ${APP}" ""
  done < <(du -sh "${USER_LIB}/Caches/"* 2>/dev/null | sort -rh | head -5)
fi

# ── 16. Papelera ──────────────────────────────────────────────────────────────
section "Papelera"

add_row "$(dir_size "${HOME}/.Trash")" \
  "Papelera (~/.Trash)" "Vaciar papelera para liberar espacio"

# ── 17. Time Machine snapshots locales ───────────────────────────────────────
section "Time Machine / Snapshots"

TM_COUNT=$(tmutil listlocalsnapshots / 2>/dev/null | grep -c 'com.apple.TimeMachine' || true)
if [[ "$TM_COUNT" -gt 0 ]]; then
  add_row "${TM_COUNT}snaps" "Time Machine snapshots locales" "Borrar: tmutil deletelocalsnapshots /"
fi

# ── 18. Simulator Runtimes (volúmenes APFS) ──────────────────────────────────
section "Simulator Runtimes (volúmenes APFS)"

_sim_tmp=$(mktemp)
diskutil apfs list > "$_sim_tmp" 2>/dev/null || true
_sim_runtime_total_kb=0
if [[ -s "$_sim_tmp" ]] && grep -q 'CoreSimulator/Volumes' "$_sim_tmp"; then
  _sim_rows=$(awk '
    /CoreSimulator\/Volumes/ { vol=$NF; sub(/.*\//, "", vol); next }
    vol && /Capacity Consumed/ && $4+0>0 {
      kb = int($4/1024)
      total += kb
      gb = kb/1024/1024
      printf "add_row \"%.1f GB\" \"Simulator Runtime: %s\" \"Borrar en Xcode > Settings > Platforms\"\n", gb, vol
      vol=""
    }
    END { print "_SIM_TOTAL_KB=" total }
  ' "$_sim_tmp")
  eval "$_sim_rows"
  _sim_runtime_total_kb=${_SIM_TOTAL_KB:-0}
fi
rm -f "$_sim_tmp"




# ── 19. Application Support ───────────────────────────────────────────────────
section "Application Support (top 10)"

APP_SUPPORT="${USER_LIB}/Application Support"
if [[ -d "$APP_SUPPORT" ]]; then
  _as_tmp=$(mktemp)
  du -shx "${APP_SUPPORT}/"* > "$_as_tmp" 2>/dev/null || true
  _as_rows=$(sort -rh "$_as_tmp" | head -10 | awk '{
    sz=$1; sub(/^[^ ]+[ \t]+/, ""); app=$0; sub(/.*\//, "", app)
    printf "add_row \"%s\" \"App Support: %s\" \"\"\n", sz, app
  }')
  eval "$_as_rows" || true
  rm -f "$_as_tmp"
fi

# ── 20. Android SDK ────────────────────────────────────────────────────────────
section "Android"

add_row "$(dir_size "${USER_LIB}/Android/sdk")"   "Android SDK" "Administrar con Android Studio > SDK Manager"

# ── 21. Applications ───────────────────────────────────────────────────────────
section "Applications (top 10)"

if [[ -d "/Applications" ]]; then
  _apps_tmp=$(mktemp)
  du -shx /Applications/* > "$_apps_tmp" 2>/dev/null || true
  _apps_rows=$(sort -rh "$_apps_tmp" | head -10 | awk '{
    sz=$1; sub(/^[^ ]+[ \t]+/, ""); app=$0; sub(/.*\//, "", app)
    printf "add_row \"%s\" \"App: %s\" \"Desinstalar si no se usa\"\n", sz, app
  }')
  eval "$_apps_rows" || true
  rm -f "$_apps_tmp"
fi

# ── 22. Group Containers ───────────────────────────────────────────────────────
section "Group Containers (top 5)"

if [[ -d "${USER_LIB}/Group Containers" ]]; then
  _gc_tmp=$(mktemp)
  du -shx "${USER_LIB}/Group Containers/"* > "$_gc_tmp" 2>/dev/null || true
  _gc_rows=$(sort -rh "$_gc_tmp" | head -5 | awk '{
    sz=$1; sub(/^[^ ]+[ \t]+/, ""); grp=$0; sub(/.*\//, "", grp)
    printf "add_row \"%s\" \"Group Container: %s\" \"\"\n", sz, grp
  }')
  eval "$_gc_rows" || true
  rm -f "$_gc_tmp"
fi

# ── Render tabla ──────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════════════╗${RESET}"
printf "${BOLD}║  %-8s  %-45s  %-16s║${RESET}\n" "Tamaño" "Descripción" "Nota"
echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════════════╣${RESET}"

IFS=$'\n' SORTED=($(printf '%s\n' "${rows[@]+${rows[@]}}" | sort -t'|' -k1 -rn))
unset IFS

TOTAL_KB=0

for row in "${SORTED[@]+${SORTED[@]}}"; do
  IFS='|' read -r kb size label note <<< "$row"
  TOTAL_KB=$((TOTAL_KB + kb))

  if   [[ $kb -gt $((10 * 1024 * 1024)) ]]; then COLOR="$RED"
  elif [[ $kb -gt $((1  * 1024 * 1024)) ]]; then COLOR="$YELLOW"
  elif [[ $kb -gt $((100 * 1024))       ]]; then COLOR="$GREEN"
  else                                           COLOR="$RESET"
  fi

  printf "${COLOR}${BOLD}  %-8s${RESET}  %-45s  ${DIM}%-16s${RESET}\n" \
    "$size" "$label" "$note"
done

echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════════════╝${RESET}"

# Total
if [[ $TOTAL_KB -gt $((1024 * 1024)) ]]; then
  TOTAL_HUMAN=$(awk "BEGIN{printf \"%.1f GB\", $TOTAL_KB / 1024 / 1024}")
elif [[ $TOTAL_KB -gt 1024 ]]; then
  TOTAL_HUMAN=$(awk "BEGIN{printf \"%.1f MB\", $TOTAL_KB / 1024}")
else
  TOTAL_HUMAN="${TOTAL_KB} KB"
fi

echo ""
echo -e "  ${BOLD}Total identificado: ${RED}${TOTAL_HUMAN}${RESET}"
echo ""
echo -e "${DIM}  Leyenda:  ${RED}■ >10 GB${RESET}${DIM}   ${YELLOW}■ 1–10 GB${RESET}${DIM}   ${GREEN}■ 100 MB–1 GB${RESET}${DIM}   ■ <100 MB${RESET}"
echo ""
rm -f "${_DISKUTIL_TMP:-}"

# ── Menú de acciones seguras ──────────────────────────────────────────────────

# Definición estática de acciones seguras.
# Formato: "Descripción|comando"
# Solo se muestran las que aplican (directorio/condición existe).
actions=()

_add_action() {
  local label="$1" cmd="$2" condition="$3" measure_path="${4:-}"
  if [[ -n "$condition" ]] && ! eval "$condition" 2>/dev/null; then
    return
  fi
  local sz="-" kb=0
  if [[ -n "$measure_path" && -e "$measure_path" ]]; then
    sz=$(du -sh "$measure_path" 2>/dev/null | awk '{print $1}' || echo "?")
    kb=$(to_kb "$sz")
  fi
  actions+=("${kb}|${sz}|${label}|${cmd}")
}

# Xcode
_add_action \
  "Borrar Xcode DerivedData" \
  "rm -rf \"${USER_LIB}/Developer/Xcode/DerivedData\"" \
  "[[ -d \"${USER_LIB}/Developer/Xcode/DerivedData\" ]]" \
  "${USER_LIB}/Developer/Xcode/DerivedData"

_add_action \
  "Borrar Xcode Caches" \
  "rm -rf \"${USER_LIB}/Caches/com.apple.dt.Xcode\"" \
  "[[ -d \"${USER_LIB}/Caches/com.apple.dt.Xcode\" ]]" \
  "${USER_LIB}/Caches/com.apple.dt.Xcode"

_add_action \
  "Borrar Xcode IB Support" \
  "rm -rf \"${USER_LIB}/Developer/Xcode/UserData/IB Support\"" \
  "[[ -d \"${USER_LIB}/Developer/Xcode/UserData/IB Support\" ]]" \
  "${USER_LIB}/Developer/Xcode/UserData/IB Support"

# iOS Simulator
_add_action \
  "Borrar CoreSimulator dyld Caches del sistema (sudo)" \
  "sudo rm -rf /Library/Developer/CoreSimulator/Caches/dyld" \
  "[[ -d /Library/Developer/CoreSimulator/Caches/dyld ]]" \
  "/Library/Developer/CoreSimulator/Caches/dyld"

_add_action \
  "Borrar CoreSimulator dyld Caches del usuario" \
  "rm -rf \"${USER_LIB}/Developer/CoreSimulator/Caches/dyld\"" \
  "[[ -d \"${USER_LIB}/Developer/CoreSimulator/Caches/dyld\" ]]" \
  "${USER_LIB}/Developer/CoreSimulator/Caches/dyld"

_add_action \
  "Eliminar simuladores iOS no disponibles" \
  "xcrun simctl delete unavailable" \
  "command -v xcrun &>/dev/null" \
  "${USER_LIB}/Developer/CoreSimulator/Devices"

if [[ ${_sim_runtime_total_kb:-0} -gt 0 ]]; then
  _sim_total_sz=$(awk -v k="$_sim_runtime_total_kb" 'BEGIN{printf "%.1f GB", k/1024/1024}')
  _sim_total_kb=$(awk -v k="$_sim_runtime_total_kb" 'BEGIN{printf "%.0f", k}')
  actions+=("${_sim_total_kb}|${_sim_total_sz}|Borrar Simulator Runtimes no usados (APFS volumes)|_clean_sim_runtimes")
fi

# Homebrew
_add_action \
  "Limpiar caché de Homebrew" \
  "brew cleanup --prune=all" \
  "command -v brew &>/dev/null" \
  "${HOME}/Library/Caches/Homebrew"

# Docker
_add_action \
  "Limpiar Docker (imágenes/contenedores sin uso)" \
  "docker system prune -f" \
  "command -v docker &>/dev/null && docker info &>/dev/null" \
  "${USER_LIB}/Containers/com.docker.docker"

# npm
_add_action \
  "Limpiar caché de npm" \
  "npm cache clean --force" \
  "command -v npm &>/dev/null" \
  "${HOME}/.npm"

# Yarn
_add_action \
  "Limpiar caché de Yarn" \
  "yarn cache clean" \
  "command -v yarn &>/dev/null" \
  "${HOME}/Library/Caches/Yarn"

# pnpm
_add_action \
  "Limpiar store de pnpm" \
  "pnpm store prune" \
  "command -v pnpm &>/dev/null" \
  "${HOME}/.pnpm-store"

# Python
_add_action \
  "Limpiar caché de pip" \
  "pip cache purge" \
  "command -v pip &>/dev/null" \
  "${HOME}/Library/Caches/pip"

_add_action \
  "Limpiar caché de uv" \
  "uv cache clean" \
  "command -v uv &>/dev/null" \
  "${HOME}/.cache/uv"

# Go
_add_action \
  "Limpiar Go build cache" \
  "go clean -cache" \
  "command -v go &>/dev/null" \
  "${HOME}/Library/Caches/go-build"

_add_action \
  "Limpiar Go module cache" \
  "go clean -modcache" \
  "command -v go &>/dev/null" \
  "${HOME}/go/pkg/mod"

# Gradle
_add_action \
  "Borrar Gradle Caches" \
  "rm -rf \"${HOME}/.gradle/caches\"" \
  "[[ -d \"${HOME}/.gradle/caches\" ]]" \
  "${HOME}/.gradle/caches"

# Unity
_add_action \
  "Borrar Unity Editor Cache" \
  "rm -rf \"${USER_LIB}/Caches/com.unity3d.UnityEditor5.x\"" \
  "[[ -d \"${USER_LIB}/Caches/com.unity3d.UnityEditor5.x\" ]]" \
  "${USER_LIB}/Caches/com.unity3d.UnityEditor5.x"

_add_action \
  "Borrar Unity Logs" \
  "rm -rf \"${USER_LIB}/Logs/Unity\"" \
  "[[ -d \"${USER_LIB}/Logs/Unity\" ]]" \
  "${USER_LIB}/Logs/Unity"

# Logs
_add_action \
  "Borrar Crash Reports" \
  "rm -rf \"${USER_LIB}/Logs/DiagnosticReports\"" \
  "[[ -d \"${USER_LIB}/Logs/DiagnosticReports\" ]]" \
  "${USER_LIB}/Logs/DiagnosticReports"

# Papelera
_add_action \
  "Vaciar Papelera" \
  "rm -rf \"${HOME}/.Trash/\"*" \
  "[[ -d \"${HOME}/.Trash\" ]]" \
  "${HOME}/.Trash"

# Library/Caches
_add_action \
  "Borrar ~/Library/Caches (caches de apps)" \
  "_clean_caches" \
  "[[ -d \"${USER_LIB}/Caches\" ]]" \
  "${USER_LIB}/Caches"

# Time Machine
_add_action \
  "Borrar snapshots locales de Time Machine" \
  "tmutil deletelocalsnapshots /" \
  "tmutil listlocalsnapshots / 2>/dev/null | grep -q 'com.apple.TimeMachine'"

# Android SDK
_add_action \
  "Borrar Android SDK" \
  "rm -rf \"${USER_LIB}/Android/sdk\"" \
  "[[ -d \"${USER_LIB}/Android/sdk\" ]]" \
  "${USER_LIB}/Android/sdk"

# JetBrains
_add_action \
  "Borrar caches de JetBrains (versiones antiguas)" \
  "rm -rf \"${USER_LIB}/Application Support/JetBrains\"" \
  "[[ -d \"${USER_LIB}/Application Support/JetBrains\" ]]" \
  "${USER_LIB}/Application Support/JetBrains"

# Spotify
_add_action \
  "Borrar datos de Spotify (se regenera)" \
  "rm -rf \"${USER_LIB}/Application Support/Spotify\"" \
  "[[ -d \"${USER_LIB}/Application Support/Spotify\" ]]" \
  "${USER_LIB}/Application Support/Spotify"

# Google Chrome/Drive cache
_add_action \
  "Borrar datos de Google (Chrome/Drive cache)" \
  "rm -rf \"${USER_LIB}/Application Support/Google\"" \
  "[[ -d \"${USER_LIB}/Application Support/Google\" ]]" \
  "${USER_LIB}/Application Support/Google"

# Unity asset cache
_add_action \
  "Borrar Unity asset cache" \
  "rm -rf \"${USER_LIB}/Unity\"" \
  "[[ -d \"${USER_LIB}/Unity\" ]]" \
  "${USER_LIB}/Unity"

}

# ── Llamada inicial ──────────────────────────────────────────────────────────
run_audit

# ── Loop del menú ─────────────────────────────────────────────────────────────
while true; do
  echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════════╗${RESET}"
  echo -e "${BOLD}${CYAN}║                     🧹  Acciones disponibles                            ║${RESET}"
  echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════════╝${RESET}"
  echo ""

  local_idx=1
  for action in "${actions[@]+${actions[@]}}"; do
    IFS='|' read -r kb sz lbl cmd <<< "$action"
    if   [[ $kb -gt $((10 * 1024 * 1024)) ]]; then SZ_COLOR="$RED"
    elif [[ $kb -gt $((1  * 1024 * 1024)) ]]; then SZ_COLOR="$YELLOW"
    elif [[ $kb -gt $((100 * 1024))       ]]; then SZ_COLOR="$GREEN"
    else                                           SZ_COLOR="$DIM"
    fi
    if [[ "$sz" == "-" ]]; then
      printf "  ${BOLD}%2d)${RESET}  %s\n" "$local_idx" "$lbl"
    else
      printf "  ${BOLD}%2d)${RESET}  ${SZ_COLOR}${BOLD}%-8s${RESET}  %s\n" "$local_idx" "$sz" "$lbl"
    fi
    (( local_idx++ ))
  done

  echo ""
  printf "  ${BOLD}%2d)${RESET}  ${DIM}Salir${RESET}\n" "$local_idx"
  echo ""
  printf "${BOLD}  Elige una opción [1-${local_idx}]: ${RESET}"
  read -r choice

  # Validar que sea número
  if ! [[ "$choice" =~ ^[0-9]+$ ]]; then
    echo -e "\n${RED}  Opción inválida.${RESET}\n"
    continue
  fi

  # Salir
  if [[ "$choice" -eq "$local_idx" ]]; then
    echo ""
    echo -e "  ${DIM}Hasta luego.${RESET}"
    echo ""
    exit 0
  fi

  # Fuera de rango
  if [[ "$choice" -lt 1 || "$choice" -gt ${#actions[@]:-0} ]]; then
    echo -e "\n${RED}  Opción fuera de rango.${RESET}\n"
    continue
  fi

  # Obtener acción seleccionada
  selected="${actions[$((choice - 1))]}"
  IFS='|' read -r _kb _sz sel_label sel_cmd <<< "$selected"

  echo ""
  echo -e "  ${YELLOW}${BOLD}Acción:${RESET}  ${sel_label}"
  echo -e "  ${DIM}Comando: ${sel_cmd}${RESET}"
  echo ""
  printf "  ${BOLD}¿Confirmar? [s/N]: ${RESET}"
  read -r confirm

  if [[ "$confirm" =~ ^[sS]$ ]]; then
    echo ""
    echo -e "  ${CYAN}Ejecutando...${RESET}"
    echo ""
    eval "$sel_cmd"
    echo ""
    echo -e "  ${GREEN}${BOLD}✓ Listo.${RESET}"
    echo ""
    printf "  ${DIM}Presiona Enter para volver a analizar...${RESET}"
    read -r
    run_audit
  else
    echo -e "  ${DIM}Cancelado.${RESET}"
  fi

  echo ""
done
