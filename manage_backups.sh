#!/system/bin/sh
# Gerenciamento completo de backups do LSPosed

source "$(dirname "$0")/core/common.sh"

# Configurações
ACTION=""
BACKUP_ID=""
TAG=""
KEEP_COUNT=10
AUTO_CLEANUP=false

usage() {
    cat <<EOF
uso: $0 [AÇÃO] [OPÇÕES]

AÇÕES:
  --create [tag]          Criar novo backup
  --list                  Listar todos os backups
  --restore <id>          Restaurar backup específico
  --delete <id>           Deletar backup específico
  --cleanup               Limpar backups antigos
  --info <id>             Informações detalhadas do backup

OPÇÕES:
  --tag <tag>            Tag personalizada para o backup
  --keep <n>             Manter últimos N backups (padrão: 10)
  --auto-cleanup         Executar limpeza automática após outras ações

EXEMPLOS:
  $0 --create "antes_do_nfcgate"
  $0 --list
  $0 --restore 3
  $0 --cleanup --keep 5
  $0 --info 1
EOF
    exit 1
}

# Parse argumentos
parse_args() {
    while [ -n "$1" ]; do
        case "$1" in
            --create) ACTION="create"; TAG="$2"; shift 2 ;;
            --list) ACTION="list"; shift ;;
            --restore) ACTION="restore"; BACKUP_ID="$2"; shift 2 ;;
            --delete) ACTION="delete"; BACKUP_ID="$2"; shift 2 ;;
            --cleanup) ACTION="cleanup"; shift ;;
            --info) ACTION="info"; BACKUP_ID="$2"; shift 2 ;;
            --tag) TAG="$2"; shift 2 ;;
            --keep) KEEP_COUNT="$2"; shift 2 ;;
            --auto-cleanup) AUTO_CLEANUP=true; shift ;;
            --help) usage ;;
            -*) log ERROR "Opção desconhecida: $1"; usage ;;
            *) log ERROR "Argumento inválido: $1"; usage ;;
        esac
    done
    
    [ -z "$ACTION" ] && usage
}

# Criar backup
create_backup() {
    local tag="${1:-manual}"
    
    if [ ! -f "$DB" ]; then
        log ERROR "Banco LSPosed não encontrado: $DB"
        return 1
    fi
    
    local backup_name="modules_config_$(date +%Y%m%d_%H%M%S).db"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    mkdir -p "$BACKUP_DIR"
    
    # Verificar integridade antes do backup
    if ! sqlite3 "$DB" "PRAGMA integrity_check;" | grep -q "ok"; then
        log ERROR "Banco corrompido - backup abortado"
        return 1
    fi
    
    # Criar backup
    cp "$DB" "$backup_path"
    
    # Verificar integridade do backup
    if ! sqlite3 "$backup_path" "PRAGMA integrity_check;" | grep -q "ok"; then
        log ERROR "Backup corrompido - removendo"
        rm -f "$backup_path"
        return 1
    fi
    
    # Metadata detalhada
    local modules_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM modules;")
    local enabled_modules=$(sqlite3 "$DB" "SELECT COUNT(*) FROM modules WHERE enabled=1;")
    local scopes_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM scope;")
    local unique_users=$(sqlite3 "$DB" "SELECT COUNT(DISTINCT user_id) FROM scope;")
    local db_size=$(stat -c %s "$backup_path")
    
    cat > "${backup_path}.meta" <<EOF
timestamp=$(date +%s)
date=$(date '+%Y-%m-%d %H:%M:%S')
tag=$tag
size=$db_size
modules_total=$modules_count
modules_enabled=$enabled_modules
scopes_total=$scopes_count
users_count=$unique_users
lsposed_version=$(getprop ro.lsposed.version 2>/dev/null || echo "unknown")
android_version=$(getprop ro.build.version.release)
created_by=lsposed-cli-tools
EOF
    
    log INFO "✅ Backup criado: $backup_name"
    log INFO "📊 $modules_count módulos ($enabled_modules ativos), $scopes_count escopos"
    echo "$backup_path"
}

# Listar backups
list_backups() {
    if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls "$BACKUP_DIR"/*.db 2>/dev/null)" ]; then
        log WARN "Nenhum backup encontrado em $BACKUP_DIR"
        return 1
    fi
    
    echo
    printf "┌─────┬─────────────────────────────────┬────────────────────┬──────────┬─────────────┬─────────┐\n"
    printf "│ %-3s │ %-31s │ %-18s │ %-8s │ %-11s │ %-7s │\n" "ID" "Nome" "Data" "Tamanho" "Módulos" "Tag"
    printf "├─────┼─────────────────────────────────┼────────────────────┼──────────┼─────────────┼─────────┤\n"
    
    local id=1
    ls "$BACKUP_DIR"/*.db 2>/dev/null | sort | while read -r backup_file; do
        local backup_name=$(basename "$backup_file")
        local meta_file="${backup_file}.meta"
        
        # Dados padrão
        local date_str="N/A"
        local size_str="N/A"
        local modules_str="N/A"
        local tag="N/A"
        
        # Ler metadata se existir
        if [ -f "$meta_file" ]; then
            local timestamp=$(grep "^timestamp=" "$meta_file" | cut -d'=' -f2)
            local file_tag=$(grep "^tag=" "$meta_file" | cut -d'=' -f2)
            local modules_total=$(grep "^modules_total=" "$meta_file" | cut -d'=' -f2)
            local modules_enabled=$(grep "^modules_enabled=" "$meta_file" | cut -d'=' -f2)
            local size=$(grep "^size=" "$meta_file" | cut -d'=' -f2)
            
            if [ -n "$timestamp" ] && [ "$timestamp" != "0" ]; then
                date_str=$(date -d "@$timestamp" '+%d/%m %H:%M' 2>/dev/null || date '+%d/%m %H:%M')
            fi
            
            if [ -n "$size" ]; then
                size_str=$(awk "BEGIN {printf \"%.1fKB\", $size/1024}")
            fi
            
            if [ -n "$modules_total" ] && [ -n "$modules_enabled" ]; then
                modules_str="${modules_enabled}/${modules_total}"
            fi
            
            tag="${file_tag:-manual}"
        else
            # Fallback para estatísticas básicas
            local file_stat=$(stat -c "%s %Y" "$backup_file" 2>/dev/null)
            if [ -n "$file_stat" ]; then
                local file_size=$(echo "$file_stat" | cut -d' ' -f1)
                local file_time=$(echo "$file_stat" | cut -d' ' -f2)
                size_str=$(awk "BEGIN {printf \"%.1fKB\", $file_size/1024}")
                date_str=$(date -d "@$file_time" '+%d/%m %H:%M' 2>/dev/null || date '+%d/%m %H:%M')
            fi
        fi
        
        # Truncar strings se muito longas
        if [ ${#backup_name} -gt 31 ]; then
            backup_name="$(echo "$backup_name" | cut -c1-28)..."
        fi
        if [ ${#tag} -gt 7 ]; then
            tag="$(echo "$tag" | cut -c1-4)..."
        fi
        
        printf "│ %-3d │ %-31s │ %-18s │ %-8s │ %-11s │ %-7s │\n" \
            "$id" "$backup_name" "$date_str" "$size_str" "$modules_str" "$tag"
        
        id=$((id + 1))
    done
    
    printf "└─────┴─────────────────────────────────┴────────────────────┴──────────┴─────────────┴─────────┘\n"
    echo
    
    # Estatísticas
    local total_backups=$(ls "$BACKUP_DIR"/*.db 2>/dev/null | wc -l)
    local total_size=$(du -sk "$BACKUP_DIR" 2>/dev/null | cut -f1)
    total_size=${total_size:-0}
    
    log INFO "📊 Total: $total_backups backup(s), $(awk "BEGIN {printf \"%.1fMB\", $total_size/1024}")"
}

# Obter backup por ID
get_backup_by_id() {
    local target_id="$1"
    local id=1
    
    ls "$BACKUP_DIR"/*.db 2>/dev/null | sort | while read -r backup_file; do
        if [ "$id" -eq "$target_id" ]; then
            echo "$backup_file"
            return 0
        fi
        id=$((id + 1))
    done
    
    return 1
}

# Restaurar backup
restore_backup() {
    local backup_id="$1"
    
    if [ -z "$backup_id" ]; then
        log ERROR "ID do backup necessário"
        return 1
    fi
    
    local backup_file=$(get_backup_by_id "$backup_id")
    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log ERROR "Backup ID $backup_id não encontrado"
        return 1
    fi
    
    local backup_name=$(basename "$backup_file")
    
    # Verificar integridade do backup
    if ! sqlite3 "$backup_file" "PRAGMA integrity_check;" | grep -q "ok"; then
        log ERROR "Backup corrompido: $backup_name"
        return 1
    fi
    
    # Backup de segurança antes da restauração
    log INFO "Criando backup de segurança antes da restauração..."
    local safety_backup=$(create_backup "before_restore_${backup_id}")
    
    # Confirmação
    echo
    log INFO "⚠️  CONFIRMAÇÃO DE RESTAURAÇÃO"
    echo "Backup a restaurar: $backup_name"
    echo "Backup de segurança: $(basename "$safety_backup")"
    echo
    printf "Tem certeza? [y/N]: "
    read -r confirm
    
    case "$confirm" in
        y|Y|yes|YES)
            log INFO "Procedendo com a restauração..."
            ;;
        *)
            log INFO "Restauração cancelada"
            return 0
            ;;
    esac
    
    # Parar LSPosed se estiver rodando
    if pgrep -f "lspd" >/dev/null; then
        log INFO "Parando LSPosed..."
        killall lspd 2>/dev/null || true
    fi
    
    # Restaurar
    cp "$backup_file" "$DB"
    
    # Verificar integridade após restauração
    if ! sqlite3 "$DB" "PRAGMA integrity_check;" | grep -q "ok"; then
        log ERROR "Falha na restauração - revertendo"
        cp "$safety_backup" "$DB"
        return 1
    fi
    
    log INFO "✅ Backup restaurado com sucesso: $backup_name"
    log INFO "🔄 Reinicialize o dispositivo para aplicar"
}

# Deletar backup
delete_backup() {
    local backup_id="$1"
    
    if [ -z "$backup_id" ]; then
        log ERROR "ID do backup necessário"
        return 1
    fi
    
    local backup_file=$(get_backup_by_id "$backup_id")
    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log ERROR "Backup ID $backup_id não encontrado"
        return 1
    fi
    
    local backup_name=$(basename "$backup_file")
    
    printf "Deletar backup '$backup_name'? [y/N]: "
    read -r confirm
    
    case "$confirm" in
        y|Y|yes|YES)
            rm -f "$backup_file" "${backup_file}.meta"
            log INFO "✅ Backup deletado: $backup_name"
            ;;
        *)
            log INFO "Operação cancelada"
            ;;
    esac
}

# Informações detalhadas do backup
show_backup_info() {
    local backup_id="$1"
    
    if [ -z "$backup_id" ]; then
        log ERROR "ID do backup necessário"
        return 1
    fi
    
    local backup_file=$(get_backup_by_id "$backup_id")
    if [ -z "$backup_file" ] || [ ! -f "$backup_file" ]; then
        log ERROR "Backup ID $backup_id não encontrado"
        return 1
    fi
    
    local backup_name=$(basename "$backup_file")
    local meta_file="${backup_file}.meta"
    
    echo
    log INFO "=== INFORMAÇÕES DO BACKUP ==="
    echo
    echo "📁 Arquivo: $backup_name"
    echo "📍 Caminho: $backup_file"
    
    if [ -f "$meta_file" ]; then
        echo
        echo "📋 Metadata:"
        while IFS='=' read -r key value; do
            case "$key" in
                timestamp) echo "    Data: $(date -d "@$value" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$value")" ;;
                tag) echo "    Tag: $value" ;;
                size) echo "    Tamanho: $(awk "BEGIN {printf \"%.2f KB\", $value/1024}")" ;;
                modules_total) echo "    Módulos total: $value" ;;
                modules_enabled) echo "    Módulos ativos: $value" ;;
                scopes_total) echo "    Escopos total: $value" ;;
                users_count) echo "    Usuários: $value" ;;
                lsposed_version) echo "    LSPosed: $value" ;;
                android_version) echo "    Android: $value" ;;
            esac
        done < "$meta_file"
    fi
    
    # Análise do banco
    echo
    echo "🔍 Análise do banco:"
    if sqlite3 "$backup_file" "PRAGMA integrity_check;" | grep -q "ok"; then
        echo "    Integridade: ✅ OK"
    else
        echo "    Integridade: ❌ Corrompido"
    fi
    
    local tables=$(sqlite3 "$backup_file" ".tables" 2>/dev/null)
    echo "    Tabelas: $tables"
    
    # Top módulos do backup
    echo
    echo "📦 Módulos no backup:"
    sqlite3 "$backup_file" "SELECT module_pkg_name, enabled FROM modules ORDER BY enabled DESC, module_pkg_name LIMIT 5;" 2>/dev/null | while IFS='|' read -r pkg enabled; do
        local status=$([ "$enabled" = "1" ] && echo "✅" || echo "⭕")
        echo "    $status $pkg"
    done
}

# Limpeza automática
cleanup_backups() {
    if [ ! -d "$BACKUP_DIR" ]; then
        log INFO "Diretório de backup não existe"
        return 0
    fi
    
    local total_backups=$(ls "$BACKUP_DIR"/*.db 2>/dev/null | wc -l)
    
    if [ "$total_backups" -le "$KEEP_COUNT" ]; then
        log INFO "Limpeza não necessária ($total_backups <= $KEEP_COUNT)"
        return 0
    fi
    
    log INFO "Limpando backups antigos (manter últimos $KEEP_COUNT)..."
    
    # Manter os mais recentes, deletar os antigos
    ls "$BACKUP_DIR"/*.db 2>/dev/null | sort | head -n "-$KEEP_COUNT" | while read -r old_backup; do
        local backup_name=$(basename "$old_backup")
        rm -f "$old_backup" "${old_backup}.meta"
        log INFO "Removido: $backup_name"
    done
    
    local remaining=$(ls "$BACKUP_DIR"/*.db 2>/dev/null | wc -l)
    log INFO "✅ Limpeza concluída: $remaining backup(s) mantido(s)"
}

# Main
main() {
    init_environment
    parse_args "$@"
    
    case "$ACTION" in
        create)
            create_backup "$TAG"
            ;;
        list)
            list_backups
            ;;
        restore)
            restore_backup "$BACKUP_ID"
            ;;
        delete)
            delete_backup "$BACKUP_ID"
            ;;
        cleanup)
            cleanup_backups
            ;;
        info)
            show_backup_info "$BACKUP_ID"
            ;;
        *)
            log ERROR "Ação inválida: $ACTION"
            usage
            ;;
    esac
    
    # Limpeza automática se solicitada
    if $AUTO_CLEANUP && [ "$ACTION" != "cleanup" ]; then
        echo
        cleanup_backups
    fi
}

main "$@"