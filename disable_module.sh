#!/system/bin/sh
# Script para desabilitar módulos LSPosed com opções avançadas

source "$(dirname "$0")/core/common.sh"
source "$(dirname "$0")/core/validation.sh"

# Configurações padrão
DRY_RUN=false
AUTO_BACKUP=true
REMOVE_SCOPES=false
FORCE=false
USER_ID=""

usage() {
    cat <<EOF
uso: $0 [OPÇÕES] <module_pkg_name> [module_pkg_name2 ...]

OPÇÕES:
  --dry-run              Preview das ações sem aplicar
  --remove-scopes        Remover também os escopos do módulo
  --user <id>            Remover escopos apenas do usuário específico
  --no-backup            Pular backup automático
  --force                Forçar desabilitação mesmo com avisos
  --help                 Mostrar esta ajuda

EXEMPLOS:
  $0 de.tu_darmstadt.seemoo.nfcgate
  $0 --remove-scopes --dry-run de.tu_darmstadt.seemoo.nfcgate
  $0 --user 0 com.ceco.pie.gravitybox
  $0 module1 module2 module3
EOF
    exit 1
}

# Parse argumentos
parse_args() {
    local modules=""
    
    while [ -n "$1" ]; do
        case "$1" in
            --dry-run) DRY_RUN=true; shift ;;
            --remove-scopes) REMOVE_SCOPES=true; shift ;;
            --user) USER_ID="$2"; shift 2 ;;
            --no-backup) AUTO_BACKUP=false; shift ;;
            --force) FORCE=true; shift ;;
            --help) usage ;;
            -*) log ERROR "Opção desconhecida: $1"; usage ;;
            *) modules="$modules $1"; shift ;;
        esac
    done
    
    if [ -z "$modules" ]; then
        log ERROR "Pelo menos um módulo deve ser especificado"
        usage
    fi
    
    MODULES="$modules"
}

# Obter informações do módulo
get_module_info() {
    local pkg="$1"
    
    local result=$(sqlite3 "$DB" "
        SELECT mid, enabled, apk_path,
               (SELECT COUNT(*) FROM scope WHERE mid = m.mid) as scope_count,
               (SELECT COUNT(DISTINCT user_id) FROM scope WHERE mid = m.mid) as user_count
        FROM modules m 
        WHERE module_pkg_name = '$pkg'
    " 2>/dev/null)
    
    if [ -z "$result" ]; then
        echo "not_found||||0|0"
    else
        echo "$result"
    fi
}

# Listar escopos do módulo
list_module_scopes() {
    local mid="$1"
    local user_filter="$2"
    
    local query="SELECT app_pkg_name, user_id FROM scope WHERE mid = $mid"
    
    if [ -n "$user_filter" ]; then
        query="$query AND user_id = $user_filter"
    fi
    
    query="$query ORDER BY user_id, app_pkg_name"
    
    sqlite3 "$DB" "$query" 2>/dev/null
}

# Verificar dependências (outros módulos que podem usar os mesmos escopos)
check_scope_dependencies() {
    local mid="$1"
    local user_filter="$2"
    
    # Obter escopos do módulo atual
    local scopes_query="SELECT DISTINCT app_pkg_name FROM scope WHERE mid = $mid"
    if [ -n "$user_filter" ]; then
        scopes_query="$scopes_query AND user_id = $user_filter"
    fi
    
    local module_scopes=$(sqlite3 "$DB" "$scopes_query" 2>/dev/null)
    
    if [ -z "$module_scopes" ]; then
        return 0
    fi
    
    # Verificar se outros módulos ativos usam os mesmos escopos
    echo "$module_scopes" | while read -r app_pkg; do
        local other_modules=$(sqlite3 "$DB" "
            SELECT DISTINCT m.module_pkg_name
            FROM scope s
            JOIN modules m ON s.mid = m.mid
            WHERE s.app_pkg_name = '$app_pkg'
            AND m.mid != $mid
            AND m.enabled = 1
        " 2>/dev/null)
        
        if [ -n "$other_modules" ]; then
            echo "$app_pkg used by: $other_modules"
        fi
    done
}

# Preview das ações
show_preview() {
    local pkg="$1"
    local mid="$2"
    local enabled="$3"
    local scope_count="$4"
    local user_count="$5"
    
    echo "📦 Módulo: $pkg (mid=$mid)"
    
    if [ "$enabled" = "0" ]; then
        echo "    Status: ⭕ Já desabilitado"
        return 0
    fi
    
    echo "    Status: ✅ Ativo → ⭕ Será desabilitado"
    
    if [ "$scope_count" -gt 0 ]; then
        echo "    Escopos: $scope_count configuração(ões) em $user_count usuário(s)"
        
        if $REMOVE_SCOPES; then
            echo "    ⚠️  Escopos serão REMOVIDOS"
            
            # Listar escopos que serão removidos
            local scopes=$(list_module_scopes "$mid" "$USER_ID")
            if [ -n "$scopes" ]; then
                echo "    Escopos a remover:"
                echo "$scopes" | while IFS='|' read -r app_pkg user_id; do
                    local status="❌"
                    if pm list packages | grep -q "package:$app_pkg"; then
                        status="📱"
                    fi
                    echo "        $status [u$user_id] $app_pkg"
                done
            fi
            
            # Verificar dependências
            local dependencies=$(check_scope_dependencies "$mid" "$USER_ID")
            if [ -n "$dependencies" ]; then
                echo "    ⚠️  Conflitos potenciais:"
                echo "$dependencies" | while read -r dep_line; do
                    echo "        $dep_line"
                done
            fi
        else
            echo "    ℹ️  Escopos serão mantidos (usar --remove-scopes para remover)"
        fi
    else
        echo "    Escopos: Nenhum configurado"
    fi
    
    echo
}

# Desabilitar módulo
disable_module() {
    local pkg="$1"
    local mid="$2"
    
    if $DRY_RUN; then
        log INFO "[DRY-RUN] Desabilitando módulo: $pkg"
        return 0
    fi
    
    # Desabilitar no banco
    sqlite3 "$DB" "UPDATE modules SET enabled = 0 WHERE mid = $mid;"
    
    if [ $? -eq 0 ]; then
        log INFO "✅ Módulo desabilitado: $pkg"
    else
        log ERROR "❌ Falha ao desabilitar módulo: $pkg"
        return 1
    fi
}

# Remover escopos
remove_module_scopes() {
    local pkg="$1"
    local mid="$2"
    
    if $DRY_RUN; then
        log INFO "[DRY-RUN] Removendo escopos do módulo: $pkg"
        return 0
    fi
    
    local delete_query="DELETE FROM scope WHERE mid = $mid"
    
    if [ -n "$USER_ID" ]; then
        delete_query="$delete_query AND user_id = $USER_ID"
        log INFO "Removendo escopos do usuário $USER_ID..."
    else
        log INFO "Removendo todos os escopos..."
    fi
    
    local removed_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM scope WHERE mid = $mid$([ -n "$USER_ID" ] && echo " AND user_id = $USER_ID");" 2>/dev/null)
    
    sqlite3 "$DB" "$delete_query;"
    
    if [ $? -eq 0 ]; then
        log INFO "✅ $removed_count escopo(s) removido(s)"
    else
        log ERROR "❌ Falha ao remover escopos"
        return 1
    fi
}

# Processar um módulo
process_module() {
    local pkg="$1"
    
    log INFO "Processando módulo: $pkg"
    
    # Validar nome do package
    if ! validate_package "$pkg"; then
        return 1
    fi
    
    # Obter informações do módulo
    local module_info=$(get_module_info "$pkg")
    local mid=$(echo "$module_info" | cut -d'|' -f1)
    local enabled=$(echo "$module_info" | cut -d'|' -f2)
    local apk_path=$(echo "$module_info" | cut -d'|' -f3)
    local scope_count=$(echo "$module_info" | cut -d'|' -f4)
    local user_count=$(echo "$module_info" | cut -d'|' -f5)
    
    # Verificar se módulo existe
    if [ "$mid" = "not_found" ]; then
        log ERROR "Módulo não encontrado no LSPosed: $pkg"
        return 1
    fi
    
    # Preview
    if $DRY_RUN || ! $FORCE; then
        show_preview "$pkg" "$mid" "$enabled" "$scope_count" "$user_count"
    fi
    
    # Verificar se já está desabilitado
    if [ "$enabled" = "0" ]; then
        if $REMOVE_SCOPES && [ "$scope_count" -gt 0 ]; then
            log INFO "Módulo já desabilitado, removendo apenas escopos..."
        else
            log WARN "Módulo $pkg já está desabilitado"
            return 0
        fi
    fi
    
    # Confirmação se não for dry-run nem force
    if ! $DRY_RUN && ! $FORCE; then
        printf "Prosseguir com $pkg? [Y/n]: "
        read -r confirm
        case "$confirm" in
            n|N|no|NO) 
                log INFO "Operação cancelada para $pkg"
                return 0
                ;;
        esac
    fi
    
    # Backup se necessário
    if $AUTO_BACKUP && ! $DRY_RUN; then
        local backup_path=$(create_auto_backup "disable_$pkg")
        log INFO "Backup criado: $(basename "$backup_path")"
    fi
    
    # Executar ações
    local success=true
    
    # Desabilitar módulo se estiver ativo
    if [ "$enabled" = "1" ]; then
        if ! disable_module "$pkg" "$mid"; then
            success=false
        fi
    fi
    
    # Remover escopos se solicitado
    if $REMOVE_SCOPES && [ "$scope_count" -gt 0 ]; then
        if ! remove_module_scopes "$pkg" "$mid"; then
            success=false
        fi
    fi
    
    if $success; then
        log INFO "✅ Processamento concluído: $pkg"
    else
        log ERROR "❌ Falhas durante o processamento: $pkg"
        return 1
    fi
}

# Main
main() {
    init_environment
    parse_args "$@"
    
    # Validação do sistema
    if ! validate_system >/dev/null; then
        log ERROR "Sistema não está pronto. Execute health_check.sh"
        exit 1
    fi
    
    # Contador de sucessos/falhas
    local total=0
    local success=0
    local failed=0
    
    # Processar cada módulo
    for module_pkg in $MODULES; do
        total=$((total + 1))
        echo
        if process_module "$module_pkg"; then
            success=$((success + 1))
        else
            failed=$((failed + 1))
        fi
    done
    
    # Sumário final
    echo
    log INFO "=== SUMÁRIO DA OPERAÇÃO ==="
    echo "📊 Total processado: $total módulo(s)"
    echo "✅ Sucessos: $success"
    echo "❌ Falhas: $failed"
    
    if $DRY_RUN; then
        echo "🔍 Modo preview - nenhuma alteração foi feita"
        echo "Execute sem --dry-run para aplicar as mudanças"
    elif [ "$success" -gt 0 ] && [ "$failed" -eq 0 ]; then
        echo "🔄 Reinicie o dispositivo para aplicar: adb shell su -c 'svc power reboot'"
    fi
    
    return $failed
}

main "$@"