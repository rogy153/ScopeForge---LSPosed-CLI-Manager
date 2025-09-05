#!/system/bin/sh
# Diagnóstico completo do sistema LSPosed

source "$(dirname "$0")/core/common.sh"
source "$(dirname "$0")/core/validation.sh"

generate_report() {
    local report_file="/data/local/tmp/lsposed-cli/health_report_$(date +%Y%m%d_%H%M%S).txt"

    cat > "$report_file" <<EOF
=================================================
RELATÓRIO DE SAÚDE - LSPosed CLI Tools
Data: $(date)
=================================================

SISTEMA:
$(uname -a)

ANDROID:
$(getprop ro.build.version.release)
SDK: $(getprop ro.build.version.sdk)

ROOT:
$(which su) ($(su --version 2>/dev/null || echo "Desconhecido"))

LSPOSED:
$([ -f "$DB" ] && echo "✅ Instalado" || echo "❌ Não encontrado")
Banco: $DB
Tamanho: $([ -f "$DB" ] && stat -c %s "$DB" || echo "N/A") bytes

MÓDULOS:
Total: $(sqlite3 "$DB" "SELECT COUNT(*) FROM modules;" 2>/dev/null || echo "N/A")
Ativos: $(sqlite3 "$DB" "SELECT COUNT(*) FROM modules WHERE enabled=1;" 2>/dev/null || echo "N/A")

ESCOPOS:
Total: $(sqlite3 "$DB" "SELECT COUNT(*) FROM scope;" 2>/dev/null || echo "N/A")
Usuários únicos: $(sqlite3 "$DB" "SELECT COUNT(DISTINCT user_id) FROM scope;" 2>/dev/null || echo "N/A")

ESPAÇO:
/data: $(df /data | tail -1 | awk '{print $4}') KB livres

DEPENDÊNCIAS:
$(check_dependencies >/dev/null 2>&1 && echo "✅ Todas OK" || echo "❌ Falhas detectadas")

=================================================
EOF

    echo "$report_file"
}

# Verificação de conectividade
check_connectivity() {
    log INFO "🌐 Verificando conectividade..."

    # Check ADB
    if pgrep -f "adbd" >/dev/null; then
        log INFO "✅ ADB daemon ativo"
    else
        log WARN "⚠️  ADB daemon não encontrado"
    fi

    # Check USB debugging
    local usb_debug=$(getprop persist.sys.usb.config)
    if echo "$usb_debug" | grep -q "adb"; then
        log INFO "✅ USB debugging habilitado"
    else
        log WARN "⚠️  USB debugging pode estar desabilitado"
    fi
}

# Verificação de performance
check_performance() {
    log INFO "⚡ Verificando performance..."

    # Uso de CPU
    local cpu_usage=$(top -n 1 | grep "CPU:" | awk '{print $2}' | cut -d'%' -f1)
    if [ -n "$cpu_usage" ] && [ "$cpu_usage" -lt 80 ]; then
        log INFO "✅ CPU: ${cpu_usage}% (OK)"
    else
        log WARN "⚠️  CPU: ${cpu_usage:-N/A}% (Alto)"
    fi

    # Uso de memória
    local mem_info=$(cat /proc/meminfo)
    local mem_total=$(echo "$mem_info" | grep "MemTotal:" | awk '{print $2}')
    local mem_free=$(echo "$mem_info" | grep "MemAvailable:" | awk '{print $2}')
    local mem_used=$((mem_total - mem_free))
    local mem_percent=$((mem_used * 100 / mem_total))

    if [ "$mem_percent" -lt 85 ]; then
        log INFO "✅ RAM: ${mem_percent}% usado (OK)"
    else
        log WARN "⚠️  RAM: ${mem_percent}% usado (Alto)"
    fi
}

# Verificação de módulos
check_modules_integrity() {
    log INFO "📦 Verificando integridade dos módulos..."

    if [ ! -f "$DB" ]; then
        log ERROR "❌ Banco LSPosed não encontrado"
        return 1
    fi

    # Módulos com APKs inexistentes
    local broken_modules=$(sqlite3 "$DB" "
        SELECT module_pkg_name, apk_path
        FROM modules
        WHERE apk_path IS NOT NULL AND apk_path != ''
    " | while IFS='|' read -r pkg apk_path; do
        if [ ! -f "$apk_path" ]; then
            echo "$pkg ($apk_path)"
        fi
    done)

    if [ -n "$broken_modules" ]; then
        log WARN "⚠️  Módulos com APKs inexistentes:"
        echo "$broken_modules" | while read -r line; do
            log WARN "    - $line"
        done
    else
        log INFO "✅ Todos os APKs dos módulos existem"
    fi

    # Escopos com apps inexistentes
    local broken_scopes=$(sqlite3 "$DB" "
        SELECT DISTINCT s.app_pkg_name
        FROM scope s
    " | while read -r app_pkg; do
        if ! pm list packages | grep -q "package:$app_pkg"; then
            echo "$app_pkg"
        fi
    done)

    if [ -n "$broken_scopes" ]; then
        log WARN "⚠️  Escopos com apps não instalados:"
        echo "$broken_scopes" | while read -r app; do
            log WARN "    - $app"
        done
    else
        log INFO "✅ Todos os apps de escopo estão instalados"
    fi
}

# Verificação de segurança
check_security() {
    log INFO "🔒 Verificando segurança..."

    # Permissões do banco
    local db_perms=$(stat -c "%a" "$DB" 2>/dev/null)
    if [ "$db_perms" = "600" ] || [ "$db_perms" = "660" ]; then
        log INFO "✅ Permissões do banco: $db_perms (OK)"
    else
        log WARN "⚠️  Permissões do banco: $db_perms (Verifique)"
    fi

    # SELinux status
    local selinux_status=$(getenforce 2>/dev/null || echo "Desconhecido")
    case "$selinux_status" in
        Enforcing) log INFO "✅ SELinux: Enforcing (Seguro)" ;;
        Permissive) log WARN "⚠️  SELinux: Permissive (Menos seguro)" ;;
        Disabled) log WARN "⚠️  SELinux: Disabled (Inseguro)" ;;
        *) log INFO "ℹ️  SELinux: $selinux_status" ;;
    esac

    # Verificar backups recentes
    local recent_backup=$(find "$BACKUP_DIR" -name "*.db" -mtime -7 2>/dev/null | wc -l)
    if [ "$recent_backup" -gt 0 ]; then
        log INFO "✅ Backups recentes: $recent_backup (última semana)"
    else
        log WARN "⚠️  Nenhum backup recente encontrado"
    fi
}

# Sugestões de otimização
suggest_optimizations() {
    log INFO "💡 Sugestões de otimização:"

    # Cache antigo
    local old_cache=$(find "$CACHE_DIR" -name "*.cache" -mtime +1 2>/dev/null | wc -l)
    if [ "$old_cache" -gt 0 ]; then
        echo "    - Limpar $old_cache arquivo(s) de cache antigo"
    fi

    # Logs antigos
    local old_logs=$(find "$(dirname "$LOG_FILE")" -name "*.log" -mtime +30 2>/dev/null | wc -l)
    if [ "$old_logs" -gt 0 ]; then
        echo "    - Limpar $old_logs arquivo(s) de log antigo"
    fi

    # Backups excessivos
    local total_backups=$(find "$BACKUP_DIR" -name "*.db" 2>/dev/null | wc -l)
    if [ "$total_backups" -gt 10 ]; then
        echo "    - Considere manter apenas os últimos 10 backups (atual: $total_backups)"
    fi

    # Módulos desabilitados com escopos
    local orphaned_scopes=$(sqlite3 "$DB" "
        SELECT COUNT(*)
        FROM scope s
        JOIN modules m ON s.mid = m.mid
        WHERE m.enabled = 0
    " 2>/dev/null)

    if [ "$orphaned_scopes" -gt 0 ]; then
        echo "    - Remover $orphaned_scopes escopo(s) de módulos desabilitados"
    fi
}

# Teste de funcionalidade
test_functionality() {
    log INFO "🧪 Testando funcionalidades..."

    # Teste de escrita no banco
    if sqlite3 "$DB" "SELECT 1;" >/dev/null 2>&1; then
        log INFO "✅ Leitura do banco: OK"
    else
        log ERROR "❌ Leitura do banco: FALHOU"
        return 1
    fi

    # Teste de backup
    local test_backup="/tmp/test_backup_$$.db"
    if cp "$DB" "$test_backup" 2>/dev/null && [ -f "$test_backup" ]; then
        rm -f "$test_backup"
        log INFO "✅ Criação de backup: OK"
    else
        log ERROR "❌ Criação de backup: FALHOU"
    fi

    # Teste de cache
    if mkdir -p "$CACHE_DIR" && touch "$CACHE_DIR/test" && rm -f "$CACHE_DIR/test"; then
        log INFO "✅ Sistema de cache: OK"
    else
        log WARN "⚠️  Sistema de cache: FALHOU"
    fi

    # Teste de manifesto
    if [ -f "$MANIFEST" ] && awk 'NR==1{exit 0} END{exit 1}' "$MANIFEST"; then
        log INFO "✅ Manifesto de escopos: OK"
    else
        log WARN "⚠️  Manifesto de escopos: AUSENTE/INVÁLIDO"
    fi
}

# Cleanup automático
auto_cleanup() {
    local cleanup_done=false

    log INFO "🧹 Executando limpeza automática..."

    # Limpar cache antigo (>24h)
    local cleaned_cache=$(find "$CACHE_DIR" -name "*.cache" -mtime +1 -delete 2>/dev/null; echo $?)
    if [ "$cleaned_cache" -eq 0 ]; then
        cleanup_done=true
    fi

    # Limpar logs antigos (>30 dias)
    local cleaned_logs=$(find "$(dirname "$LOG_FILE")" -name "*.log" -mtime +30 -delete 2>/dev/null; echo $?)
    if [ "$cleaned_logs" -eq 0 ]; then
        cleanup_done=true
    fi

    if $cleanup_done; then
        log INFO "✅ Limpeza automática concluída"
    else
        log INFO "ℹ️  Nenhuma limpeza necessária"
    fi
}

main() {
    init_environment

    log INFO "🏥 Iniciando diagnóstico de saúde do sistema..."
    echo

    # Executar verificações
    validate_system
    local validation_status=$?

    echo
    check_connectivity
    echo
    check_performance
    echo
    check_modules_integrity
    echo
    check_security
    echo
    test_functionality
    local test_status=$?

    echo
    suggest_optimizations
    echo
    auto_cleanup

    # Gerar relatório
    local report=$(generate_report)
    log INFO "📋 Relatório detalhado salvo em: $report"

    # Status final
    echo
    if [ $validation_status -eq 0 ] && [ $test_status -eq 0 ]; then
        log INFO "🎉 DIAGNÓSTICO: Sistema saudável e operacional!"
        echo "✅ Pronto para usar os scripts LSPosed CLI"
    else
        log WARN "⚠️  DIAGNÓSTICO: Sistema funcional mas com problemas detectados"
        echo "📋 Consulte o relatório para detalhes: $report"
    fi

    return $validation_status
}

main "$@"
