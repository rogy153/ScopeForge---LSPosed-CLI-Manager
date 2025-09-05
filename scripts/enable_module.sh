#!/system/bin/sh
# Script melhorado para habilitar módulos com escopos

source "$(dirname "$0")/core/common.sh"
source "$(dirname "$0")/core/validation.sh"

# Configurações padrão
USER_ID=0
MODE="manual"
DRY_RUN=false
AUTO_BACKUP=true
FORCE=false
MULTI_USER=false

usage() {
    cat <<EOF
uso: $0 [OPÇÕES] <module_pkg_name> [app_pkg ...]

MODOS:
  --auto              Aplica todas as sugestões automaticamente
  --choose            Modo interativo para seleção
  (padrão)            Modo manual com apps explícitos

OPÇÕES:
  --dry-run           Preview das ações sem aplicar
  --user <id>         User ID específico (padrão: 0)
  --multi-user        Aplica em múltiplos usuários interativamente
  --no-backup         Pula backup automático
  --force             Força aplicação mesmo com avisos
  --help              Mostra esta ajuda

EXEMPLOS:
  $0 --auto de.tu_darmstadt.seemoo.nfcgate
  $0 --choose --multi-user de.tu_darmstadt.seemoo.nfcgate
  $0 --dry-run --auto de.tu_darmstadt.seemoo.nfcgate
  $0 de.tu_darmstadt.seemoo.nfcgate com.android.nfc com.android.systemui
EOF
    exit 1
}

# Parse argumentos melhorado
parse_args() {
    while [ -n "$1" ]; do
        case "$1" in
            --auto) MODE="auto"; shift ;;
            --choose) MODE="choose"; shift ;;
            --dry-run) DRY_RUN=true; shift ;;
            --user) USER_ID="$2"; shift 2 ;;
            --multi-user) MULTI_USER=true; shift ;;
            --no-backup) AUTO_BACKUP=false; shift ;;
            --force) FORCE=true; shift ;;
            --help) usage ;;
            -*|--*) log ERROR "Opção desconhecida: $1"; usage ;;
            *) break ;;
        esac
    done
    
    [ -z "$1" ] && usage
    MODULE_PKG="$1"; shift
    EXPLICIT_APPS="$*"
}

# Descoberta de escopos melhorada
discover_scopes() {
    local pkg="$1"
    local suggest=""
    
    if [ ! -f "$MANIFEST" ]; then
        log WARN "Manifesto não encontrado. Usando descoberta básica."
        return 0
    fi
    
    # Cache de packages
    local packages=$(get_installed_packages)
    
    # Extração YAML melhorada
    local defaults=$(awk -v pkg="$pkg" '
        $0 ~ "^\\s*" pkg ":\\s*$" {inmod=1; next}
        inmod && $0 ~ /^\\s*[^#[:space:]]+:\\s*$/ && $0 !~ "^\\s*" pkg ":\\s*$" {inmod=0}
        inmod && $0 ~ /^\\s*defaults:\\s*$/ {inlist=1; next}
        inlist && $0 ~ /^\\s*-/ {gsub(/^\\s*-\\s*/, "", $0); print $0; next}
        inlist && $0 !~ /^\\s*-/ {inlist=0}
    ' "$MANIFEST")
    
    local patterns=$(awk -v pkg="$pkg" '
        $0 ~ "^\\s*" pkg ":\\s*$" {inmod=1; next}
        inmod && $0 ~ /^\\s*[^#[:space:]]+:\\s*$/ && $0 !~ "^\\s*" pkg ":\\s*$" {inmod=0}
        inmod && $0 ~ /^\\s*patterns:\\s*$/ {inlist=1; next}
        inlist && $0 ~ /^\\s*-/ {gsub(/^\\s*-\\s*/, "", $0); print $0; next}
        inlist && $0 !~ /^\\s*-/ {inlist=0}
    ' "$MANIFEST")
    
    # Combinar defaults + patterns
    suggest="$(printf '%s\n' "$defaults"
    echo "$patterns" | while read -r pat; do
        [ -z "$pat" ] && continue
        echo "$packages" | grep -iE "$pat" || true
    done | sort -u)"
    
    # Filtrar vazios e validar
    echo "$suggest" | while read -r app; do
        [ -n "$app" ] && validate_scope "$app" >/dev/null 2>&1 && echo "$app"
    done | sort -u
}

# Interface interativa melhorada
interactive_selection() {
    local suggestions="$1"
    local module_pkg="$2"
    
    if [ -z "$suggestions" ]; then
        log WARN "Nenhuma sugestão disponível para $module_pkg"
        return 0
    fi
    
    log INFO "Escopos sugeridos para: $module_pkg"
    
    # Tabela formatada
    echo
    printf "┌─────┬────────────────────────────┬──────────────┬────────────┐\n"
    printf "│ %-3s │ %-26s │ %-12s │ %-10s │\n" "ID" "Package" "Tipo" "Status"
    printf "├─────┼────────────────────────────┼──────────────┼────────────┤\n"
    
    local i=1
    echo "$suggestions" | while read -r app; do
        local tipo="Sistema"
        local status="Instalado"
        
        case "$app" in
            com.android.*) tipo="Sistema" ;;
            com.google.*) tipo="Google" ;;
            *) tipo="Vendor" ;;
        esac
        
        if ! get_installed_packages | grep -qx "$app"; then
            status="Ausente"
        fi
        
        printf "│ [%-1d] │ %-26s │ %-12s │ %-10s │\n" "$i" "$app" "$tipo" "$status"
        i=$((i+1))
    done
    
    printf "└─────┴────────────────────────────┴──────────────┴────────────┘\n"
    echo
    
    # Seleção
    printf "Seleção ([a]ll, [n]one, números): "
    read -r selection
    
    case "$selection" in
        a|all) echo "$suggestions" ;;
        n|none) return 0 ;;
        *) 
            # Parse números/ranges
            echo "$suggestions" | awk -v sel="$selection" '
            BEGIN {
                split(sel, parts, ",")
                for (i in parts) {
                    if (match(parts[i], /^([0-9]+)-([0-9]+)$/)) {
                        start = substr(parts[i], RSTART, RLENGTH-1)
                        end = substr(parts[i], RSTART+length(start)+1)
                        for (j=start; j<=end; j++) selected[j] = 1
                    } else if (match(parts[i], /^[0-9]+$/)) {
                        selected[parts[i]] = 1
                    }
                }
            }
            NR in selected {print $0}
            '
            ;;
    esac
}

# Multi-usuário interativo
select_users() {
    if ! $MULTI_USER; then
        echo "$USER_ID"
        return
    fi
    
    # Detectar usuários disponíveis
    local available_users=$(pm list users | grep -oE 'UserInfo\{[0-9]+' | grep -oE '[0-9]+' | sort -n)
    
    log INFO "Usuários disponíveis:"
    echo "$available_users" | while read -r uid; do
        local user_type="Primário"
        [ "$uid" != "0" ] && user_type="Secundário/Work"
        echo "  [$uid] User $uid ($user_type)"
    done
    
    printf "Selecionar usuários (ex: 0,10 ou 0-10): "
    read -r user_selection
    
    # Parse seleção
    echo "$user_selection" | tr ',' '\n' | while read -r part; do
        if echo "$part" | grep -qE '^[0-9]+-[0-9]+$'; then
            start=$(echo "$part" | cut -d'-' -f1)
            end=$(echo "$part" | cut -d'-' -f2)
            seq "$start" "$end"
        else
            echo "$part"
        fi
    done | sort -nu
}

# Aplicação de escopos
apply_scopes() {
    local module_pkg="$1"
    local apps="$2"
    local users="$3"
    
    if $DRY_RUN; then
        log INFO "[DRY-RUN] Simulando aplicação para: $module_pkg"
        return 0
    fi
    
    # Backup
    if $AUTO_BACKUP; then
        local backup_path=$(create_auto_backup "enable_$module_pkg")
        log INFO "Backup criado: $(basename "$backup_path")"
    fi
    
    # Obter MID
    local mid=$(sqlite3 "$DB" "SELECT mid FROM modules WHERE module_pkg_name='$module_pkg';")
    
    # Habilitar módulo
    sqlite3 "$DB" "UPDATE modules SET enabled=1 WHERE module_pkg_name='$module_pkg';"
    log INFO "Módulo habilitado: $module_pkg (mid=$mid)"
    
    # Aplicar escopos
    echo "$apps" | while read -r app; do
        [ -z "$app" ] && continue
        echo "$users" | while read -r uid; do
            [ -z "$uid" ] && continue
            sqlite3 "$DB" "INSERT OR IGNORE INTO scope(mid, app_pkg_name, user_id) VALUES($mid, '$app', $uid);"
            log INFO "Escopo adicionado: $app (user $uid)"
        done
    done
}

# Main
main() {
    init_environment
    parse_args "$@"
    
    log INFO "Iniciando configuração do módulo: $MODULE_PKG"
    
    # Validações
    if ! validate_system >/dev/null; then
        log ERROR "Sistema não está pronto. Execute health_check.sh"
        exit 1
    fi
    
    if ! validate_module "$MODULE_PKG"; then
        exit 1
    fi
    
    # Descoberta de escopos
    local suggested_apps=""
    local users_to_apply=$(select_users)
    
    case "$MODE" in
        manual)
            if [ -z "$EXPLICIT_APPS" ]; then
                log ERROR "Modo manual requer apps explícitos"
                exit 1
            fi
            suggested_apps="$EXPLICIT_APPS"
            ;;
        auto)
            suggested_apps=$(discover_scopes "$MODULE_PKG")
            if [ -z "$suggested_apps" ]; then
                log WARN "Nenhum escopo descoberto automaticamente"
                exit 0
            fi
            ;;
        choose)
            local suggestions=$(discover_scopes "$MODULE_PKG")
            suggested_apps=$(interactive_selection "$suggestions" "$MODULE_PKG")
            ;;
    esac
    
    # Preview/Confirmação
    if $DRY_RUN || [ "$MODE" = "choose" ]; then
        echo
        log INFO "=== PREVIEW DA OPERAÇÃO ==="
        echo "📦 Módulo: $MODULE_PKG"
        echo "👥 Usuários: $(echo "$users_to_apply" | tr '\n' ',' | sed 's/,$//')"
        echo "🎯 Escopos:"
        echo "$suggested_apps" | while read -r app; do
            [ -n "$app" ] && echo "    - $app"
        done
        echo "💾 Backup: $($AUTO_BACKUP && echo "SIM" || echo "NÃO")"
        echo
        
        if ! $DRY_RUN; then
            printf "Prosseguir? [Y/n]: "
            read -r confirm
            case "$confirm" in
                n|N|no|NO) log INFO "Operação cancelada"; exit 0 ;;
            esac
        fi
    fi
    
    # Aplicação
    apply_scopes "$MODULE_PKG" "$suggested_apps" "$users_to_apply"
    
    if ! $DRY_RUN; then
        log INFO "✅ Configuração concluída!"
        log INFO "🔄 Reinicie o dispositivo para aplicar: adb shell su -c 'svc power reboot'"
    fi
}

main "$@"