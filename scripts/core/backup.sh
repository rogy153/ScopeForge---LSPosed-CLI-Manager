#!/system/bin/sh
# Sistema avançado de backup e restore para LSPosed

source "$(dirname "$0")/common.sh"

# Configurações específicas de backup
BACKUP_RETENTION_DAYS=30
MAX_BACKUPS=50
COMPRESSION_ENABLED=true
ENCRYPTION_ENABLED=false
BACKUP_VERIFICATION=true

# Estrutura de backup avançada
create_structured_backup() {
    local tag="${1:-manual}"
    local include_logs="${2:-false}"
    local include_cache="${3:-false}"
    
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="$BACKUP_DIR/backup_$timestamp"
    local backup_archive="$BACKUP_DIR/backup_${timestamp}.tar.gz"
    
    log INFO "Criando backup estruturado: $timestamp"
    
    # Criar diretório temporário
    mkdir -p "$backup_dir"
    
    # 1. Banco principal
    if [ -f "$DB" ]; then
        # Verificar integridade antes do backup
        if ! sqlite3 "$DB" "PRAGMA integrity_check;" | grep -q "ok"; then
            log ERROR "Banco corrompido - backup abortado"
            rm -rf "$backup_dir"
            return 1
        fi
        
        cp "$DB" "$backup_dir/modules_config.db"
        log INFO "✅ Banco LSPosed copiado"
    else
        log ERROR "Banco LSPosed não encontrado"
        rm -rf "$backup_dir"
        return 1
    fi
    
    # 2. Configuração LSPosed
    local lspd_config_dir="/data/adb/lspd"
    if [ -d "$lspd_config_dir" ]; then
        mkdir -p "$backup_dir/lspd_config"
        
        # Configurações principais
        for config_file in "config.json" "whitelist.json" "blacklist.json"; do
            if [ -f "$lspd_config_dir/$config_file" ]; then
                cp "$lspd_config_dir/$config_file" "$backup_dir/lspd_config/"
                log INFO "✅ Configuração copiada: $config_file"
            fi
        done
        
        # Logs do LSPosed (se solicitado)
        if $include_logs && [ -d "$lspd_config_dir/logs" ]; then
            cp -r "$lspd_config_dir/logs" "$backup_dir/lspd_logs"
            log INFO "✅ Logs LSPosed incluídos"
        fi
    fi
    
    # 3. Módulos instalados (APKs)
    log INFO "Coletando informações dos módulos..."
    mkdir -p "$backup_dir/modules"
    
    sqlite3 "$DB" "SELECT module_pkg_name, apk_path FROM modules WHERE apk_path IS NOT NULL;" 2>/dev/null | while IFS='|' read -r pkg apk_path; do
        if [ -f "$apk_path" ]; then
            local module_dir="$backup_dir/modules/$pkg"
            mkdir -p "$module_dir"
            cp "$apk_path" "$module_dir/module.apk"
            
            # Informações do módulo
            cat > "$module_dir/info.txt" <<EOF
Package: $pkg
APK Path: $apk_path
Size: $(stat -c %s "$apk_path" 2>/dev/null || echo "0") bytes
Backup Date: $(date)
EOF
        fi
    done
    
    # 4. Manifesto personalizado (se existir)
    if [ -f "$MANIFEST" ]; then
        cp "$MANIFEST" "$backup_dir/scopes_manifest.yml"
        log INFO "✅ Manifesto de escopos incluído"
    fi
    
    # 5. Cache do CLI (se solicitado)
    if $include_cache && [ -d "$CACHE_DIR" ]; then
        cp -r "$CACHE_DIR" "$backup_dir/cli_cache"
        log INFO "✅ Cache CLI incluído"
    fi
    
    # 6. Informações do sistema
    cat > "$backup_dir/system_info.txt" <<EOF
# LSPosed CLI Tools - Backup System Info
Backup Date: $(date)
Backup Tag: $tag
Android Version: $(getprop ro.build.version.release)
SDK Level: $(getprop ro.build.version.sdk)
LSPosed Version: $(getprop ro.lsposed.version 2>/dev/null || echo "unknown")
Device: $(getprop ro.product.model)
ROM: $(getprop ro.build.display.id)
Architecture: $(getprop ro.product.cpu.abi)

# Estatísticas do backup
Total Modules: $(sqlite3 "$DB" "SELECT COUNT(*) FROM modules;" 2>/dev/null)
Active Modules: $(sqlite3 "$DB" "SELECT COUNT(*) FROM modules WHERE enabled=1;" 2>/dev/null)
Total Scopes: $(sqlite3 "$DB" "SELECT COUNT(*) FROM scope;" 2>/dev/null)
Unique Users: $(sqlite3 "$DB" "SELECT COUNT(DISTINCT user_id) FROM scope;" 2>/dev/null)

# Backup Options
Include Logs: $include_logs
Include Cache: $include_cache
Compression: $COMPRESSION_ENABLED
Verification: $BACKUP_VERIFICATION
EOF
    
    # 7. Metadata detalhada
    create_backup_metadata "$backup_dir" "$tag"
    
    # 8. Script de restore
    create_restore_script "$backup_dir" "$timestamp"
    
    # 9. Compressão (se habilitada)
    if $COMPRESSION_ENABLED; then
        log INFO "Comprimindo backup..."
        tar -czf "$backup_archive" -C "$BACKUP_DIR" "backup_$timestamp"
        
        if [ $? -eq 0 ]; then
            rm -rf "$backup_dir"
            local final_size=$(stat -c %s "$backup_archive" | awk '{printf "%.2f MB", $1/1024/1024}')
            log INFO "✅ Backup comprimido: $final_size"
            echo "$backup_archive"
        else
            log ERROR "Falha na compressão"
            rm -f "$backup_archive"
            echo "$backup_dir"
        fi
    else
        echo "$backup_dir"
    fi
}

# Criar metadata expandida
create_backup_metadata() {
    local backup_dir="$1"
    local tag="$2"
    
    cat > "$backup_dir/metadata.json" <<EOF
{
  "backup_info": {
    "timestamp": $(date +%s),
    "date_human": "$(date)",
    "tag": "$tag",
    "format_version": "2.0",
    "cli_version": "1.0.0",
    "backup_type": "structured"
  },
  "system_info": {
    "android_version": "$(getprop ro.build.version.release)",
    "sdk_level": $(getprop ro.build.version.sdk),
    "lsposed_version": "$(getprop ro.lsposed.version 2>/dev/null || echo "unknown")",
    "device_model": "$(getprop ro.product.model)",
    "rom_version": "$(getprop ro.build.display.id)",
    "architecture": "$(getprop ro.product.cpu.abi)"
  },
  "database_stats": {
    "total_modules": $(sqlite3 "$DB" "SELECT COUNT(*) FROM modules;" 2>/dev/null),
    "active_modules": $(sqlite3 "$DB" "SELECT COUNT(*) FROM modules WHERE enabled=1;" 2>/dev/null),
    "total_scopes": $(sqlite3 "$DB" "SELECT COUNT(*) FROM scope;" 2>/dev/null),
    "unique_users": $(sqlite3 "$DB" "SELECT COUNT(DISTINCT user_id) FROM scope;" 2>/dev/null),
    "db_size_bytes": $(stat -c %s "$DB" 2>/dev/null || echo "0")
  },
  "modules": [
$(sqlite3 "$DB" "SELECT module_pkg_name, enabled, apk_path FROM modules;" 2>/dev/null | while IFS='|' read -r pkg enabled apk_path; do
    cat <<MODULE_EOF
    {
      "package": "$pkg",
      "enabled": $([ "$enabled" = "1" ] && echo "true" || echo "false"),
      "apk_path": "$apk_path",
      "scopes_count": $(sqlite3 "$DB" "SELECT COUNT(*) FROM scope WHERE mid=(SELECT mid FROM modules WHERE module_pkg_name='$pkg');" 2>/dev/null)
    }
MODULE_EOF
done | sed '$ ! s/$/,/')
  ]
}
EOF
}

# Criar script de restore automatizado
create_restore_script() {
    local backup_dir="$1"
    local timestamp="$2"
    
    cat > "$backup_dir/restore.sh" <<'RESTORE_EOF'
#!/system/bin/sh
# Script de restore automático
# Gerado pelo LSPosed CLI Tools

set -e

BACKUP_DIR="$(dirname "$0")"
DB="/data/adb/lspd/config/modules_config.db"

log() {
    echo "[$(date '+%H:%M:%S')] $*"
}

# Verificar root
if [ "$(id -u)" -ne 0 ]; then
    echo "Erro: Root necessário para restore"
    exit 1
fi

log "Iniciando restore do backup..."

# Parar LSPosed
if pgrep -f "lspd" >/dev/null; then
    log "Parando LSPosed..."
    killall lspd 2>/dev/null || true
    sleep 2
fi

# Backup de segurança
if [ -f "$DB" ]; then
    log "Criando backup de segurança..."
    cp "$DB" "${DB}.pre_restore_$(date +%Y%m%d_%H%M%S)"
fi

# Restaurar banco
if [ -f "$BACKUP_DIR/modules_config.db" ]; then
    log "Restaurando banco LSPosed..."
    cp "$BACKUP_DIR/modules_config.db" "$DB"
    
    # Verificar integridade
    if ! sqlite3 "$DB" "PRAGMA integrity_check;" | grep -q "ok"; then
        log "Erro: Banco restaurado está corrompido"
        exit 1
    fi
    
    log "✅ Banco restaurado com sucesso"
else
    log "Erro: Banco não encontrado no backup"
    exit 1
fi

# Restaurar configurações LSPosed
if [ -d "$BACKUP_DIR/lspd_config" ]; then
    log "Restaurando configurações LSPosed..."
    cp -r "$BACKUP_DIR/lspd_config"/* "/data/adb/lspd/" 2>/dev/null || true
fi

# Restaurar manifesto
if [ -f "$BACKUP_DIR/scopes_manifest.yml" ]; then
    log "Restaurando manifesto de escopos..."
    mkdir -p "/data/local/tmp/lsposed-cli/data"
    cp "$BACKUP_DIR/scopes_manifest.yml" "/data/local/tmp/lsposed-cli/data/"
fi

log "✅ Restore concluído!"
log "🔄 Reinicie o dispositivo para aplicar as mudanças"

RESTORE_EOF

    chmod +x "$backup_dir/restore.sh"
}

# Verificar integridade do backup
verify_backup() {
    local backup_path="$1"
    
    log INFO "Verificando integridade do backup..."
    
    # Se for arquivo comprimido
    if echo "$backup_path" | grep -q '\.tar\.gz$'; then
        if ! tar -tzf "$backup_path" >/dev/null 2>&1; then
            log ERROR "Arquivo comprimido corrompido"
            return 1
        fi
        
        # Extrair temporariamente para verificação
        local temp_dir="/tmp/backup_verify_$$"
        mkdir -p "$temp_dir"
        tar -xzf "$backup_path" -C "$temp_dir"
        backup_path="$temp_dir/$(tar -tzf "$backup_path" | head -1 | cut -d'/' -f1)"
    fi
    
    # Verificar estrutura
    local required_files="modules_config.db metadata.json system_info.txt restore.sh"
    for file in $required_files; do
        if [ ! -f "$backup_path/$file" ]; then
            log ERROR "Arquivo obrigatório ausente: $file"
            return 1
        fi
    done
    
    # Verificar integridade do banco
    if ! sqlite3 "$backup_path/modules_config.db" "PRAGMA integrity_check;" | grep -q "ok"; then
        log ERROR "Banco no backup está corrompido"
        return 1
    fi
    
    # Limpar temporário se criado
    if [ -d "/tmp/backup_verify_$$" ]; then
        rm -rf "/tmp/backup_verify_$$"
    fi
    
    log INFO "✅ Backup íntegro"
    return 0
}

# Restore estruturado
restore_structured_backup() {
    local backup_path="$1"
    local selective="${2:-false}"
    
    log INFO "Iniciando restore estruturado..."
    
    # Verificar integridade primeiro
    if ! verify_backup "$backup_path"; then
        log ERROR "Backup inválido ou corrompido"
        return 1
    fi
    
    # Preparar diretório de trabalho
    local work_dir="/tmp/restore_work_$$"
    mkdir -p "$work_dir"
    
    # Extrair se necessário
    if echo "$backup_path" | grep -q '\.tar\.gz$'; then
        tar -xzf "$backup_path" -C "$work_dir"
        backup_path="$work_dir/$(tar -tzf "$backup_path" | head -1 | cut -d'/' -f1)"
    fi
    
    # Ler metadata
    if [ -f "$backup_path/metadata.json" ]; then
        log INFO "Informações do backup:"
        grep -E '"date_human"|"tag"|"android_version"|"total_modules"' "$backup_path/metadata.json" | while read -r line; do
            echo "    $line"
        done
    fi
    
    # Confirmação
    if ! $selective; then
        echo
        printf "Continuar com o restore? [y/N]: "
        read -r confirm
        case "$confirm" in
            y|Y|yes|YES) ;;
            *) log INFO "Restore cancelado"; rm -rf "$work_dir"; return 0 ;;
        esac
    fi
    
    # Backup de segurança
    log INFO "Criando backup de segurança..."
    local safety_backup=$(create_auto_backup "before_restore_$(date +%Y%m%d_%H%M%S)")
    
    # Parar LSPosed
    if pgrep -f "lspd" >/dev/null; then
        log INFO "Parando LSPosed..."
        killall lspd 2>/dev/null || true
        sleep 2
    fi
    
    # Restaurar banco principal
    if [ -f "$backup_path/modules_config.db" ]; then
        log INFO "Restaurando banco LSPosed..."
        cp "$backup_path/modules_config.db" "$DB"
        
        # Verificar após restore
        if ! sqlite3 "$DB" "PRAGMA integrity_check;" | grep -q "ok"; then
            log ERROR "Falha no restore - revertendo"
            cp "$safety_backup" "$DB"
            rm -rf "$work_dir"
            return 1
        fi
        
        log INFO "✅ Banco restaurado"
    fi
    
    # Restaurar configurações LSPosed
    if [ -d "$backup_path/lspd_config" ]; then
        log INFO "Restaurando configurações LSPosed..."
        cp -r "$backup_path/lspd_config"/* "/data/adb/lspd/" 2>/dev/null || true
        log INFO "✅ Configurações restauradas"
    fi
    
    # Restaurar manifesto
    if [ -f "$backup_path/scopes_manifest.yml" ]; then
        log INFO "Restaurando manifesto de escopos..."
        mkdir -p "$(dirname "$MANIFEST")"
        cp "$backup_path/scopes_manifest.yml" "$MANIFEST"
        log INFO "✅ Manifesto restaurado"
    fi
    
    # Limpar
    rm -rf "$work_dir"
    
    log INFO "✅ Restore estruturado concluído!"
    log INFO "🔄 Reinicie o dispositivo para aplicar as mudanças"
    log INFO "💾 Backup de segurança: $(basename "$safety_backup")"
    
    return 0
}

# Limpeza automática de backups antigos
cleanup_old_backups() {
    local keep_days="${1:-$BACKUP_RETENTION_DAYS}"
    local max_count="${2:-$MAX_BACKUPS}"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        log INFO "Diretório de backup não existe"
        return 0
    fi
    
    log INFO "Limpando backups antigos (>${keep_days} dias, max ${max_count})..."
    
    # Remover por idade
    local removed_by_age=0
    find "$BACKUP_DIR" -name "*.db" -o -name "*.tar.gz" -o -type d -name "backup_*" | while read -r backup_item; do
        local age_days=$((($(date +%s) - $(stat -c %Y "$backup_item")) / 86400))
        if [ "$age_days" -gt "$keep_days" ]; then
            rm -rf "$backup_item"
            log INFO "Removido por idade: $(basename "$backup_item") (${age_days} dias)"
            removed_by_age=$((removed_by_age + 1))
        fi
    done
    
    # Remover por quantidade (manter os mais recentes)
    local total_backups=$(find "$BACKUP_DIR" -maxdepth 1 \( -name "*.db" -o -name "*.tar.gz" -o -type d -name "backup_*" \) | wc -l)
    
    if [ "$total_backups" -gt "$max_count" ]; then
        local to_remove=$((total_backups - max_count))
        log INFO "Removendo $to_remove backup(s) mais antigo(s)..."
        
        find "$BACKUP_DIR" -maxdepth 1 \( -name "*.db" -o -name "*.tar.gz" -o -type d -name "backup_*" \) -printf '%T@ %p\n' | sort -n | head -n "$to_remove" | while read -r timestamp backup_item; do
            rm -rf "$(echo "$backup_item" | cut -d' ' -f2-)"
            log INFO "Removido por quantidade: $(basename "$(echo "$backup_item" | cut -d' ' -f2-)")"
        done
    fi
    
    # Estatísticas finais
    local remaining=$(find "$BACKUP_DIR" -maxdepth 1 \( -name "*.db" -o -name "*.tar.gz" -o -type d -name "backup_*" \) | wc -l)
    local total_size=$(du -sk "$BACKUP_DIR" 2>/dev/null | cut -f1)
    total_size=${total_size:-0}
    
    log INFO "✅ Limpeza concluída: $remaining backup(s), $(awk "BEGIN {printf \"%.1fMB\", $total_size/1024}")"
}

# Exportar configuração
export_configuration() {
    local output_file="$1"
    local include_scopes="${2:-true}"
    
    log INFO "Exportando configuração para: $output_file"
    
    cat > "$output_file" <<EOF
# LSPosed Configuration Export
# Generated: $(date)
# Device: $(getprop ro.product.model)
# Android: $(getprop ro.build.version.release)

[modules]
EOF

    # Listar módulos
    sqlite3 "$DB" "SELECT module_pkg_name, enabled FROM modules ORDER BY module_pkg_name;" 2>/dev/null | while IFS='|' read -r pkg enabled; do
        echo "$pkg = $([ "$enabled" = "1" ] && echo "enabled" || echo "disabled")" >> "$output_file"
    done
    
    if $include_scopes; then
        echo "" >> "$output_file"
        echo "[scopes]" >> "$output_file"
        
        sqlite3 "$DB" "
            SELECT m.module_pkg_name, s.app_pkg_name, s.user_id
            FROM scope s
            JOIN modules m ON s.mid = m.mid
            ORDER BY m.module_pkg_name, s.user_id, s.app_pkg_name
        " 2>/dev/null | while IFS='|' read -r module app user_id; do
            echo "$module -> $app (user $user_id)" >> "$output_file"
        done
    fi
    
    log INFO "✅ Configuração exportada"
}

# Importar configuração
import_configuration() {
    local config_file="$1"
    local dry_run="${2:-false}"
    
    if [ ! -f "$config_file" ]; then
        log ERROR "Arquivo de configuração não encontrado: $config_file"
        return 1
    fi
    
    log INFO "Importando configuração de: $config_file"
    
    if ! $dry_run; then
        # Backup de segurança
        create_auto_backup "before_import_$(date +%Y%m%d_%H%M%S)" >/dev/null
    fi
    
    # Processar seção [modules]
    awk '/^\[modules\]$/,/^\[/ { if (!/^\[/ && NF > 0 && !/^#/) print }' "$config_file" | while read -r line; do
        local module=$(echo "$line" | cut -d'=' -f1 | tr -d ' ')
        local status=$(echo "$line" | cut -d'=' -f2 | tr -d ' ')
        
        if [ -n "$module" ] && [ -n "$status" ]; then
            if $dry_run; then
                log INFO "[DRY-RUN] $module -> $status"
            else
                # Aplicar configuração
                local enabled_value=0
                [ "$status" = "enabled" ] && enabled_value=1
                
                sqlite3 "$DB" "UPDATE modules SET enabled = $enabled_value WHERE module_pkg_name = '$module';" 2>/dev/null
                if [ $? -eq 0 ]; then
                    log INFO "✅ $module -> $status"
                else
                    log WARN "⚠️  Falha ao configurar: $module"
                fi
            fi
        fi
    done
    
    if $dry_run; then
        log INFO "Preview concluído - use sem --dry-run para aplicar"
    else
        log INFO "✅ Importação concluída"
    fi
}
