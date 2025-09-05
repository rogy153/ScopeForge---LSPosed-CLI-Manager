#!/system/bin/sh
# Operações em lote para múltiplos módulos LSPosed

source "$(dirname "$0")/core/common.sh"
source "$(dirname "$0")/core/validation.sh"

# Configurações padrão
OPERATION=""
DRY_RUN=false
AUTO_BACKUP=true
FORCE=false
MODULES_FILE=""
SCOPE_MODE="auto"
USER_ID=0
BATCH_SIZE=5

usage() {
    cat <<EOF
uso: $0 <OPERAÇÃO> [OPÇÕES] [modules...]

OPERAÇÕES:
  --enable               Habilitar módulos em lote
  --disable              Desabilitar módulos em lote
  --toggle               Alternar status dos módulos
  --reset-scopes         Resetar escopos de múltiplos módulos
  --cleanup              Limpeza geral (módulos órfãos, escopos inválidos)

OPÇÕES:
  --file <arquivo>       Ler lista de módulos de arquivo (um por linha)
  --scope-mode <modo>    Para --enable: auto, manual, interactive
  --user <id>            User ID para operações (padrão: 0)
  --batch-size <n>       Processar N módulos por vez (padrão: 5)
  --dry-run              Preview das operações sem aplicar
  --no-backup            Pular backup automático
  --force                Não pedir confirmações

FORMATOS DE ARQUIVO:
  # Comentários são ignorados
  de.tu_darmstadt.seemoo.nfcgate
  com.ceco.pie.gravitybox
  # Módulo com escopos específicos (apenas para --enable)
  tk.wasdennnoch.androidn_ify:com.android.systemui,android

EXEMPLOS:
  $0 --enable --scope-mode auto module1 module2 module3
  $0 --disable --file /sdcard/modules_to_disable.txt
  $0 --toggle com.ceco.pie.gravitybox tk.wasdennnoch.androidn_ify
  $0 --cleanup --dry-run
  $0 --reset-scopes --user 0 module1 module2
EOF
    exit 1
}

# Parse argumentos
parse_args() {
    while [ -n "$1" ]; do
        case "$1" in
            --enable) OPERATION="enable"; shift ;;
            --disable) OPERATION="disable"; shift ;;
            --toggle) OPERATION="toggle"; shift ;;
            --reset-scopes) OPERATION="reset_scopes"; shift ;;
            --cleanup) OPERATION="cleanup"; shift ;;
            --file) MODULES_FILE="$2"; shift 2 ;;
            --scope-mode) SCOPE_MODE="$2"; shift 2 ;;
            --user) USER_ID="$2"; shift 2 ;;
            --batch-size) BATCH_SIZE="$2"; shift 2 ;;
            --dry-run) DRY_RUN=true; shift ;;
            --no-backup) AUTO_BACKUP=false; shift ;;
            --force) FORCE=true; shift ;;
            --help) usage ;;
            -*) log ERROR "Opção desconhecida: $1"; usage ;;
            *) MODULES_LIST="$MODULES_LIST $1"; shift ;;
        esac
    done
    
    if [ -z "$OPERATION" ]; then
        log ERROR "Operação deve ser especificada"
        usage
    fi
}

# Ler módulos de arquivo
read_modules_file() {
    local file="$1"
    
    if [ ! -f "$file" ]; then
        log ERROR "Arquivo não encontrado: $file"
        return 1
    fi
    
    # Processar arquivo, ignorando comentários e linhas vazias
    grep -v '^#' "$file" | grep -v '^[[:space:]]*$' | while read -r line; do
        # Remover espaços em branco
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        echo "$line"
    done
}

# Obter lista final de módulos
get_modules_list() {
    local final_list=""
    
    # Módulos da linha de comando
    if [ -n "$MODULES_LIST" ]; then
        final_list="$MODULES_LIST"
    fi
    
    # Módulos do arquivo
    if [ -n "$MODULES_FILE" ]; then
        local file_modules=$(read_modules_file "$MODULES_FILE")
        if [ $? -eq 0 ]; then
            final_list="$final_list $file_modules"
        else
            return 1
        fi
    fi
    
    # Se nenhum módulo especificado, usar todos (apenas para algumas operações)
    if [ -z "$final_list" ]; then
        case "$OPERATION" in
            cleanup|toggle)
                final_list=$(sqlite3 "$DB" "SELECT module_pkg_name FROM modules ORDER BY module_pkg_name;" 2>/dev/null)
                ;;
            *)
                log ERROR "Lista de módulos necessária para operação: $OPERATION"
                return 1
                ;;
        esac
    fi
    
    echo "$final_list"
}

# Validar módulos
validate_modules() {
    local modules="$1"
    local valid_modules=""
    local invalid_count=0
    
    for module in $modules; do
        # Separar módulo de escopos específicos (formato: module:scope1,scope2)
        local module_pkg=$(echo "$module" | cut -d':' -f1)
        
        if validate_package "$module_pkg" && sqlite3 "$DB" "SELECT 1 FROM modules WHERE module_pkg_name='$module_pkg';" >/dev/null 2>&1; then
            valid_modules="$valid_modules $module"
        else
            log WARN "Módulo inválido ignorado: $module_pkg"
            invalid_count=$((invalid_count + 1))
        fi
    done
    
    if [ "$invalid_count" -gt 0 ]; then
        log WARN "$invalid_count módulo(s) inválido(s) ignorado(s)"
    fi
    
    echo "$valid_modules"
}

# Obter status do módulo
get_module_status() {
    local pkg="$1"
    
    sqlite3 "$DB" "SELECT enabled FROM modules WHERE module_pkg_name='$pkg';" 2>/dev/null
}

# Habilitar módulos em lote
bulk_enable() {
    local modules="$1"
    local success=0
    local failed=0
    
    for module in $modules; do
        local module_pkg=$(echo "$module" | cut -d':' -f1)
        local specific_scopes=$(echo "$module" | cut -d':' -f2 | tr ',' ' ')
        
        log INFO "Habilitando: $module_pkg"
        
        # Preparar comando
        local cmd="$(dirname "$0")/enable_module.sh"
        
        if $DRY_RUN; then
            cmd="$cmd --dry-run"
        fi
        
        if ! $AUTO_BACKUP; then
            cmd="$cmd --no-backup"
        fi
        
        cmd="$cmd --user $USER_ID"
        
        # Determinar modo de escopos
        if echo "$module" | grep -q ':'; then
            # Escopos específicos fornecidos
            cmd="$cmd $module_pkg $specific_scopes"
        else
            case "$SCOPE_MODE" in
                auto) cmd="$cmd --auto $module_pkg" ;;
                manual) cmd="$cmd $module_pkg" ;;
                interactive) cmd="$cmd --choose $module_pkg" ;;
                *) log ERROR "Modo de escopo inválido: $SCOPE_MODE"; return 1 ;;
            esac
        fi
        
        # Executar
        if $cmd >/dev/null 2>&1; then
            log INFO "✅ $module_pkg habilitado"
            success=$((success + 1))
        else
            log ERROR "❌ Falha ao habilitar $module_pkg"
            failed=$((failed + 1))
        fi
        
        # Pausa entre operações para não sobrecarregar
        sleep 0.5
    done
    
    echo "$success $failed"
}

# Desabilitar módulos em lote
bulk_disable() {
    local modules="$1"
    local success=0
    local failed=0
    
    for module in $modules; do
        local module_pkg=$(echo "$module" | cut -d':' -f1)
        
        log INFO "Desabilitando: $module_pkg"
        
        # Preparar comando
        local cmd="$(dirname "$0")/disable_module.sh"
        
        if $DRY_RUN; then
            cmd="$cmd --dry-run"
        fi
        
        if ! $AUTO_BACKUP; then
            cmd="$cmd --no-backup"
        fi
        
        if $FORCE; then
            cmd="$cmd --force"
        fi
        
        cmd="$cmd $module_pkg"
        
        # Executar
        if $cmd >/dev/null 2>&1; then
            log INFO "✅ $module_pkg desabilitado"
            success=$((success + 1))
        else
            log ERROR "❌ Falha ao desabilitar $module_pkg"
            failed=$((failed + 1))
        fi
        
        sleep 0.5
    done
    
    echo "$success $failed"
}

# Alternar status dos módulos
bulk_toggle() {
    local modules="$1"
    local enabled_list=""
    local disabled_list=""
    
    # Separar por status atual
    for module in $modules; do
        local module_pkg=$(echo "$module" | cut -d':' -f1)
        local status=$(get_module_status "$module_pkg")
        
        if [ "$status" = "1" ]; then
            disabled_list="$disabled_list $module_pkg"
        else
            enabled_list="$enabled_list $module_pkg"
        fi
    done
    
    # Processar listas
    local total_success=0
    local total_failed=0
    
    if [ -n "$disabled_list" ]; then
        log INFO "Desabilitando módulos ativos..."
        local result=$(bulk_disable "$disabled_list")
        local success=$(echo "$result" | cut -d' ' -f1)
        local failed=$(echo "$result" | cut -d' ' -f2)
        total_success=$((total_success + success))
        total_failed=$((total_failed + failed))
    fi
    
    if [ -n "$enabled_list" ]; then
        log INFO "Habilitando módulos inativos..."
        local result=$(bulk_enable "$enabled_list")
        local success=$(echo "$result" | cut -d' ' -f1)
        local failed=$(echo "$result" | cut -d' ' -f2)
        total_success=$((total_success + success))
        total_failed=$((total_failed + failed))
    fi
    
    echo "$total_success $total_failed"
}

# Resetar escopos
bulk_reset_scopes() {
    local modules="$1"
    local success=0
    local failed=0
    
    for module in $modules; do
        local module_pkg=$(echo "$module" | cut -d':' -f1)
        local mid=$(sqlite3 "$DB" "SELECT mid FROM modules WHERE module_pkg_name='$module_pkg';" 2>/dev/null)
        
        if [ -z "$mid" ]; then
            log ERROR "Módulo não encontrado: $module_pkg"
            failed=$((failed + 1))
            continue
        fi
        
        log INFO "Resetando escopos: $module_pkg"
        
        if ! $DRY_RUN; then
            # Backup
            if $AUTO_BACKUP; then
                create_auto_backup "reset_scopes_$module_pkg" >/dev/null
            fi
            
            # Remover escopos existentes
            local delete_query="DELETE FROM scope WHERE mid = $mid"
            if [ -n "$USER_ID" ]; then
                delete_query="$delete_query AND user_id = $USER_ID"
            fi
            
            sqlite3 "$DB" "$delete_query;"
            
            if [ $? -eq 0 ]; then
                log INFO "✅ Escopos resetados: $module_pkg"
                success=$((success + 1))
            else
                log ERROR "❌ Falha ao resetar escopos: $module_pkg"
                failed=$((failed + 1))
            fi
        else
            log INFO "[DRY-RUN] Escopos seriam resetados: $module_pkg"
            success=$((success + 1))
        fi
    done
    
    echo "$success $failed"
}

# Limpeza geral
bulk_cleanup() {
    local success=0
    local failed=0
    
    log INFO "Iniciando limpeza geral do sistema..."
    
    if $AUTO_BACKUP && ! $DRY_RUN; then
        create_auto_backup "cleanup_$(date +%Y%m%d_%H%M%S)" >/dev/null
    fi
    
    # 1. Remover escopos de apps não instalados
    log INFO "1. Removendo escopos de apps não instalados..."
    local invalid_scopes=$(sqlite3 "$DB" "SELECT DISTINCT app_pkg_name FROM scope;" 2>/dev/null | while read -r app_pkg; do
        if ! pm list packages | grep -q "package:$app_pkg"; then
            echo "$app_pkg"
        fi
    done)
    
    if [ -n "$invalid_scopes" ]; then
        local count=0
        echo "$invalid_scopes" | while read -r app_pkg; do
            if ! $DRY_RUN; then
                sqlite3 "$DB" "DELETE FROM scope WHERE app_pkg_name = '$app_pkg';"
            fi
            log INFO "Removido escopo inválido: $app_pkg"
            count=$((count + 1))
        done
        success=$((success + count))
    else
        log INFO "Nenhum escopo inválido encontrado"
    fi
    
    # 2. Remover escopos de módulos desabilitados (opcional)
    log INFO "2. Verificando escopos órfãos..."
    local orphaned_scopes=$(sqlite3 "$DB" "
        SELECT COUNT(*)
        FROM scope s
        JOIN modules m ON s.mid = m.mid
        WHERE m.enabled = 0
    " 2>/dev/null)
    
    if [ "$orphaned_scopes" -gt 0 ]; then
        if $FORCE || ! $DRY_RUN; then
            if ! $DRY_RUN; then
                sqlite3 "$DB" "
                    DELETE FROM scope 
                    WHERE mid IN (SELECT mid FROM modules WHERE enabled = 0)
                "
            fi
            log INFO "Removidos $orphaned_scopes escopo(s) órfão(s)"
            success=$((success + orphaned_scopes))
        else
            log WARN "$orphaned_scopes escopo(s) órfão(s) encontrado(s) (use --force para remover)"
        fi
    fi
    
    # 3. Verificar integridade do banco
    log INFO "3. Verificando integridade do banco..."
    if sqlite3 "$DB" "PRAGMA integrity_check;" | grep -q "ok"; then
        log INFO "✅ Integridade do banco: OK"
    else
        log ERROR "❌ Banco corrompido detectado"
        failed=$((failed + 1))
    fi
    
    # 4. Otimizar banco (VACUUM)
    if ! $DRY_RUN && [ "$failed" -eq 0 ]; then
        log INFO "4. Otimizando banco de dados..."
        sqlite3 "$DB" "VACUUM;"
        if [ $? -eq 0 ]; then
            log INFO "✅ Banco otimizado"
        else
            log WARN "⚠️  Falha na otimização do banco"
        fi
    fi
    
    echo "$success $failed"
}

# Processar em lotes
process_in_batches() {
    local modules="$1"
    local operation="$2"
    local total_modules=$(echo "$modules" | wc -w)
    local processed=0
    local total_success=0
    local total_failed=0
    
    # Converter string em array temporário
    echo "$modules" > /tmp/modules_list_$$.tmp
    
    while [ $processed -lt $total_modules ]; do
        # Obter próximo lote
        local batch=$(echo "$modules" | tr ' ' '\n' | sed -n "$((processed + 1)),$((processed + BATCH_SIZE))p" | tr '\n' ' ')
        local batch_size=$(echo "$batch" | wc -w)
        
        if [ -z "$batch" ]; then
            break
        fi
        
        log INFO "=== LOTE $((processed / BATCH_SIZE + 1)): $batch_size módulo(s) ==="
        
        local result=""
        case "$operation" in
            enable) result=$(bulk_enable "$batch") ;;
            disable) result=$(bulk_disable "$batch") ;;
            toggle) result=$(bulk_toggle "$batch") ;;
            reset_scopes) result=$(bulk_reset_scopes "$batch") ;;
            cleanup) result=$(bulk_cleanup) ;;
        esac
        
        local success=$(echo "$result" | cut -d' ' -f1)
        local failed=$(echo "$result" | cut -d' ' -f2)
        
        total_success=$((total_success + success))
        total_failed=$((total_failed + failed))
        processed=$((processed + batch_size))
        
        # Pausa entre lotes
        if [ $processed -lt $total_modules ]; then
            log INFO "Pausando 2s entre lotes..."
            sleep 2
        fi
    done
    
    rm -f /tmp/modules_list_$$.tmp
    echo "$total_success $total_failed"
}

# Preview da operação
show_operation_preview() {
    local modules="$1"
    local operation="$2"
    local count=$(echo "$modules" | wc -w)
    
    echo
    log INFO "=== PREVIEW DA OPERAÇÃO EM LOTE ==="
    echo "📋 Operação: $operation"
    echo "📊 Total de módulos: $count"
    echo "👤 Usuário: $USER_ID"
    echo "⚙️  Modo escopos: $SCOPE_MODE"
    echo "📦 Tamanho do lote: $BATCH_SIZE"
    echo "💾 Backup automático: $($AUTO_BACKUP && echo "SIM" || echo "NÃO")"
    echo
    
    echo "📋 Módulos a processar:"
    local i=1
    for module in $modules; do
        local module_pkg=$(echo "$module" | cut -d':' -f1)
        local current_status=$(get_module_status "$module_pkg")
        local status_text="❓"
        
        case "$current_status" in
            1) status_text="✅ Ativo" ;;
            0) status_text="⭕ Inativo" ;;
            *) status_text="❌ N/F" ;;
        esac
        
        printf "    %2d. %-30s %s\n" "$i" "$module_pkg" "$status_text"
        i=$((i + 1))
        
        # Limitar preview a 20 módulos
        if [ $i -gt 20 ]; then
            echo "    ... e mais $((count - 20)) módulo(s)"
            break
        fi
    done
    echo
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
    
    # Obter lista de módulos
    local modules=$(get_modules_list)
    if [ $? -ne 0 ] || [ -z "$modules" ]; then
        log ERROR "Nenhum módulo válido para processar"
        exit 1
    fi
    
    # Validar módulos
    modules=$(validate_modules "$modules")
    if [ -z "$modules" ]; then
        log ERROR "Nenhum módulo válido após validação"
        exit 1
    fi
    
    # Preview
    show_operation_preview "$modules" "$OPERATION"
    
    # Confirmação
    if ! $DRY_RUN && ! $FORCE; then
        printf "Prosseguir com a operação em lote? [y/N]: "
        read -r confirm
        case "$confirm" in
            y|Y|yes|YES) ;;
            *) log INFO "Operação cancelada"; exit 0 ;;
        esac
    fi
    
    # Executar operação
    local start_time=$(date +%s)
    local result=$(process_in_batches "$modules" "$OPERATION")
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    local total_success=$(echo "$result" | cut -d' ' -f1)
    local total_failed=$(echo "$result" | cut -d' ' -f2)
    
    # Sumário final
    echo
    log INFO "=== SUMÁRIO DA OPERAÇÃO EM LOTE ==="
    echo "⏱️  Duração: ${duration}s"
    echo "✅ Sucessos: $total_success"
    echo "❌ Falhas: $total_failed"
    
    if $DRY_RUN; then
        echo "🔍 Modo preview - nenhuma alteração foi feita"
    elif [ "$total_success" -gt 0 ]; then
        echo "🔄 Reinicie o dispositivo para aplicar mudanças"
    fi
    
    return $total_failed
}

main "$@"