#!/system/bin/sh
# Sistema de validação e checks de integridade

source "$(dirname "$0")/core/common.sh"

# Validação completa do sistema
validate_system() {
    local errors=0

    log INFO "Iniciando validação do sistema..."

    # Check 1: Root
    if [ "$(id -u)" -eq 0 ]; then
        log INFO "✅ Root: OK"
    else
        log ERROR "❌ Root: FALHOU - Execute com su"
        ((errors++))
    fi

    # Check 2: LSPosed
    if [ -f "$DB" ]; then
        log INFO "✅ LSPosed: Banco encontrado"

        # Check integridade do banco
        if sqlite3 "$DB" "PRAGMA integrity_check;" | grep -q "ok"; then
            log INFO "✅ Banco LSPosed: Integridade OK"
        else
            log ERROR "❌ Banco LSPosed: Corrompido"
            ((errors++))
        fi

        # Check tabelas essenciais
        local tables=$(sqlite3 "$DB" ".tables" 2>/dev/null)
        if echo "$tables" | grep -q "modules" && echo "$tables" | grep -q "scope"; then
            log INFO "✅ Tabelas LSPosed: OK"
        else
            log ERROR "❌ Tabelas LSPosed: Não encontradas"
            log ERROR "Tabelas disponíveis: $tables"
            ((errors++))
        fi
    else
        log ERROR "❌ LSPosed: Banco não encontrado em $DB"
        ((errors++))
    fi

    # Check 3: SQLite3
    if command -v sqlite3 >/dev/null 2>&1; then
        log INFO "✅ SQLite3: $(sqlite3 --version | cut -d' ' -f1-2)"
    else
        log ERROR "❌ SQLite3: Não encontrado"
        ((errors++))
    fi

    # Check 4: Espaço em disco
    local free_space=$(df /data | tail -1 | awk '{print $4}')
    if [ "$free_space" -gt 10240 ]; then  # 10MB
        log INFO "✅ Espaço livre: $(($free_space/1024))MB"
    else
        log WARN "⚠️  Espaço baixo: $(($free_space/1024))MB"
    fi

    # Check 5: Permissões
    if [ -r "$DB" ] && [ -w "$DB" ]; then
        log INFO "✅ Permissões do banco: OK"
    else
        log ERROR "❌ Permissões do banco: Sem acesso"
        ((errors++))
    fi

    # Check 6: Módulos ativos
    local active_modules=$(sqlite3 "$DB" "SELECT COUNT(*) FROM modules WHERE enabled=1;")
    log INFO "📊 Módulos ativos: $active_modules"

    # Check 7: Escopos configurados
    local total_scopes=$(sqlite3 "$DB" "SELECT COUNT(*) FROM scope;")
    log INFO "📊 Escopos configurados: $total_scopes"

    # Resultado final
    if [ $errors -eq 0 ]; then
        log INFO "🎉 Validação concluída: Sistema OK"
        return 0
    else
        log ERROR "💥 Validação falhou: $errors erro(s) encontrado(s)"
        return 1
    fi
}

# Validação de módulo específico
validate_module() {
    local pkg="$1"

    if ! validate_package "$pkg"; then
        return 1
    fi

    # Check se existe no banco
    local mid=$(sqlite3 "$DB" "SELECT mid FROM modules WHERE module_pkg_name='$pkg';" 2>/dev/null)
    if [ -z "$mid" ]; then
        log ERROR "Módulo não encontrado no LSPosed: $pkg"
        return 1
    fi

    # Check se APK existe
    local apk_path=$(sqlite3 "$DB" "SELECT apk_path FROM modules WHERE module_pkg_name='$pkg';")
    if [ -n "$apk_path" ] && [ ! -f "$apk_path" ]; then
        log WARN "APK do módulo não encontrado: $apk_path"
    fi

    log INFO "Módulo válido: $pkg (mid=$mid)"
    return 0
}

# Validação de escopo
validate_scope() {
    local app_pkg="$1"

    if ! validate_package "$app_pkg"; then
        return 1
    fi

    # Check se está instalado
    if get_installed_packages | grep -qx "$app_pkg"; then
        log INFO "App de escopo instalado: $app_pkg"
        return 0
    else
        log WARN "App de escopo NÃO instalado: $app_pkg"
        return 1
    fi
}

# Check de dependências do sistema
check_dependencies() {
    local deps_ok=true

    # Lista de comandos necessários
    local required_cmds="sqlite3 pm grep awk sed"

    for cmd in $required_cmds; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log INFO "✅ $cmd: $(command -v "$cmd")"
        else
            log ERROR "❌ $cmd: Não encontrado"
            deps_ok=false
        fi
    done

    $deps_ok
}
