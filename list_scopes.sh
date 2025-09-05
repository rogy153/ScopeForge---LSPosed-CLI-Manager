#!/system/bin/sh
# Lista escopos aplicados aos módulos LSPosed

source "$(dirname "$0")/core/common.sh"

# Configurações padrão
MODULE_FILTER=""
USER_FILTER=""
APP_FILTER=""
SHOW_DETAILS=false
OUTPUT_FORMAT="table"
SORT_BY="module"
ONLY_INSTALLED=false

usage() {
    cat <<EOF
uso: $0 [OPÇÕES] [MODULE_PKG]

FILTROS:
  --module <pkg>         Filtrar por módulo específico
  --user <id>            Filtrar por usuário específico
  --app <pkg>            Filtrar por app de escopo específico
  --only-installed       Apenas escopos de apps instalados

INFORMAÇÕES:
  --details              Informações detalhadas dos apps de escopo
  --sort <campo>         Ordenar por: module, app, user, status

FORMATOS:
  --format <tipo>        Saída: table, list, json, minimal

EXEMPLOS:
  $0 --module de.tu_darmstadt.seemoo.nfcgate
  $0 --user 0 --details
  $0 --app com.android.systemui
  $0 --only-installed --sort app
EOF
    exit 1
}

# Parse argumentos
parse_args() {
    while [ -n "$1" ]; do
        case "$1" in
            --module) MODULE_FILTER="$2"; shift 2 ;;
            --user) USER_FILTER="$2"; shift 2 ;;
            --app) APP_FILTER="$2"; shift 2 ;;
            --only-installed) ONLY_INSTALLED=true; shift ;;
            --details) SHOW_DETAILS=true; shift ;;
            --sort) SORT_BY="$2"; shift 2 ;;
            --format) OUTPUT_FORMAT="$2"; shift 2 ;;
            --help) usage ;;
            -*) log ERROR "Opção desconhecida: $1"; usage ;;
            *) MODULE_FILTER="$1"; shift ;;
        esac
    done
}

# Obter informações detalhadas do app
get_app_details() {
    local app_pkg="$1"
    local version="N/A"
    local status="missing"
    local size="N/A"
    local label="N/A"
    
    # Verificar se está instalado
    if pm list packages | grep -q "package:$app_pkg"; then
        status="installed"
        
        if $SHOW_DETAILS; then
            # Versão
            version=$(dumpsys package "$app_pkg" 2>/dev/null | grep -E "versionName=" | head -1 | cut -d'=' -f2 | tr -d ' ')
            
            # Tamanho do APK
            local apk_path=$(pm path "$app_pkg" 2>/dev/null | head -1 | cut -d':' -f2)
            if [ -n "$apk_path" ] && [ -f "$apk_path" ]; then
                size=$(stat -c %s "$apk_path" 2>/dev/null | awk '{printf "%.1fMB", $1/1024/1024}')
            fi
            
            # Label (nome amigável)
            label=$(dumpsys package "$app_pkg" 2>/dev/null | grep -E "applicationInfo.*label=" | head -1 | sed 's/.*label=//' | cut -d' ' -f1)
        fi
    fi
    
    echo "$version|$status|$size|$label"
}

# Categorizar app
categorize_app() {
    local app_pkg="$1"
    
    case "$app_pkg" in
        android) echo "core" ;;
        com.android.systemui) echo "systemui" ;;
        com.android.settings) echo "settings" ;;
        com.android.nfc) echo "nfc" ;;
        com.android.*) echo "system" ;;
        com.google.*) echo "google" ;;
        com.samsung.*|com.sec.*) echo "samsung" ;;
        com.xiaomi.*|com.miui.*) echo "xiaomi" ;;
        *launcher*) echo "launcher" ;;
        *camera*) echo "camera" ;;
        *) echo "user" ;;
    esac
}

# Construir query SQL
build_query() {
    local base_query="
        SELECT m.module_pkg_name, s.app_pkg_name, s.user_id, m.enabled, m.mid
        FROM scope s 
        JOIN modules m ON s.mid = m.mid
    "
    
    local where_clauses=""
    
    if [ -n "$MODULE_FILTER" ]; then
        where_clauses="$where_clauses AND m.module_pkg_name = '$MODULE_FILTER'"
    fi
    
    if [ -n "$USER_FILTER" ]; then
        where_clauses="$where_clauses AND s.user_id = $USER_FILTER"
    fi
    
    if [ -n "$APP_FILTER" ]; then
        where_clauses="$where_clauses AND s.app_pkg_name = '$APP_FILTER'"
    fi
    
    # Remover primeiro 'AND'
    where_clauses=$(echo "$where_clauses" | sed 's/^ AND//')
    
    if [ -n "$where_clauses" ]; then
        base_query="$base_query WHERE $where_clauses"
    fi
    
    # Ordenação
    case "$SORT_BY" in
        module) base_query="$base_query ORDER BY m.module_pkg_name, s.user_id, s.app_pkg_name" ;;
        app) base_query="$base_query ORDER BY s.app_pkg_name, m.module_pkg_name, s.user_id" ;;
        user) base_query="$base_query ORDER BY s.user_id, m.module_pkg_name, s.app_pkg_name" ;;
        status) base_query="$base_query ORDER BY m.enabled DESC, m.module_pkg_name, s.app_pkg_name" ;;
        *) base_query="$base_query ORDER BY m.module_pkg_name, s.user_id, s.app_pkg_name" ;;
    esac
    
    echo "$base_query"
}

# Filtrar apenas apps instalados
filter_installed_only() {
    local scopes_data="$1"
    
    if ! $ONLY_INSTALLED; then
        echo "$scopes_data"
        return
    fi
    
    echo "$scopes_data" | while IFS='|' read -r module_pkg app_pkg user_id enabled mid; do
        if pm list packages | grep -q "package:$app_pkg"; then
            echo "$module_pkg|$app_pkg|$user_id|$enabled|$mid"
        fi
    done
}

# Formato tabela
format_table() {
    local scopes_data="$1"
    
    if [ -z "$scopes_data" ]; then
        log WARN "Nenhum escopo encontrado com os filtros aplicados"
        return 1
    fi
    
    echo
    if $SHOW_DETAILS; then
        printf "┌─────────────────────────────────┬─────────────────────────────────┬────┬──────────┬─────────┬─────────┬─────────┐\n"
        printf "│ %-31s │ %-31s │ %-2s │ %-8s │ %-7s │ %-7s │ %-7s │\n" "Módulo" "App de Escopo" "U" "Status" "Versão" "Tamanho" "Categoria"
        printf "├─────────────────────────────────┼─────────────────────────────────┼────┼──────────┼─────────┼─────────┼─────────┤\n"
    else
        printf "┌─────────────────────────────────┬─────────────────────────────────┬────┬──────────┐\n"
        printf "│ %-31s │ %-31s │ %-2s │ %-8s │\n" "Módulo" "App de Escopo" "U" "Status"
        printf "├─────────────────────────────────┼─────────────────────────────────┼────┼──────────┤\n"
    fi
    
    echo "$scopes_data" | while IFS='|' read -r module_pkg app_pkg user_id enabled mid; do
        # Truncar nomes se muito longos
        local short_module="$module_pkg"
        if [ ${#module_pkg} -gt 31 ]; then
            short_module="$(echo "$module_pkg" | cut -c1-28)..."
        fi
        
        local short_app="$app_pkg"
        if [ ${#app_pkg} -gt 31 ]; then
            short_app="$(echo "$app_pkg" | cut -c1-28)..."
        fi
        
        # Status do módulo
        local module_status=""
        if [ "$enabled" = "1" ]; then
            module_status="✅ ON"
        else
            module_status="⭕ OFF"
        fi
        
        if $SHOW_DETAILS; then
            # Obter detalhes do app
            local app_details=$(get_app_details "$app_pkg")
            local version=$(echo "$app_details" | cut -d'|' -f1)
            local app_status=$(echo "$app_details" | cut -d'|' -f2)
            local size=$(echo "$app_details" | cut -d'|' -f3)
            local category=$(categorize_app "$app_pkg")
            
            # Ícone do status do app
            local app_status_icon=""
            case "$app_status" in
                installed) app_status_icon="📱" ;;
                missing) app_status_icon="❌" ;;
            esac
            
            printf "│ %-31s │ %-31s │ %-2s │ %-8s │ %-7s │ %-7s │ %-7s │\n" \
                "$short_module" "$short_app" "$user_id" "$module_status" "$version" "$size" "$category"
        else
            printf "│ %-31s │ %-31s │ %-2s │ %-8s │\n" \
                "$short_module" "$short_app" "$user_id" "$module_status"
        fi
    done
    
    if $SHOW_DETAILS; then
        printf "└─────────────────────────────────┴─────────────────────────────────┴────┴──────────┴─────────┴─────────┴─────────┘\n"
    else
        printf "└─────────────────────────────────┴─────────────────────────────────┴────┴──────────┘\n"
    fi
    
    echo
    echo "Legenda: U=User ID, ✅=Módulo ativo, ⭕=Módulo inativo"
}

# Formato lista hierárquico
format_list() {
    local scopes_data="$1"
    
    local current_module=""
    local current_user=""
    
    echo "$scopes_data" | while IFS='|' read -r module_pkg app_pkg user_id enabled mid; do
        # Cabeçalho do módulo
        if [ "$module_pkg" != "$current_module" ]; then
            current_module="$module_pkg"
            echo
            local status_icon="⭕"
            [ "$enabled" = "1" ] && status_icon="✅"
            echo "$status_icon $module_pkg (mid=$mid)"
        fi
        
        # Cabeçalho do usuário
        if [ "$user_id" != "$current_user" ]; then
            current_user="$user_id"
            echo "  👤 User $user_id:"
        fi
        
        # App de escopo
        local app_status=""
        if pm list packages | grep -q "package:$app_pkg"; then
            app_status="📱"
        else
            app_status="❌"
        fi
        
        echo "    $app_status $app_pkg"
    done
}

# Formato minimal
format_minimal() {
    local scopes_data="$1"
    
    echo "$scopes_data" | while IFS='|' read -r module_pkg app_pkg user_id enabled mid; do
        echo "$app_pkg"
    done | sort -u
}

# Formato JSON
format_json() {
    local scopes_data="$1"
    
    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"filters\": {"
    echo "    \"module\": \"${MODULE_FILTER:-null}\","
    echo "    \"user\": ${USER_FILTER:-null},"
    echo "    \"app\": \"${APP_FILTER:-null}\","
    echo "    \"only_installed\": $ONLY_INSTALLED"
    echo "  },"
    echo "  \"scopes\": ["
    
    local first=true
    echo "$scopes_data" | while IFS='|' read -r module_pkg app_pkg user_id enabled mid; do
        if $first; then
            first=false
        else
            echo ","
        fi
        
        local app_details=""
        if $SHOW_DETAILS; then
            app_details=$(get_app_details "$app_pkg")
        fi
        
        cat <<EOF
    {
      "module": {
        "package": "$module_pkg",
        "mid": $mid,
        "enabled": $([ "$enabled" = "1" ] && echo "true" || echo "false")
      },
      "scope": {
        "app_package": "$app_pkg",
        "user_id": $user_id,
        "category": "$(categorize_app "$app_pkg")"
EOF
        
        if $SHOW_DETAILS && [ -n "$app_details" ]; then
            local version=$(echo "$app_details" | cut -d'|' -f1)
            local status=$(echo "$app_details" | cut -d'|' -f2)
            local size=$(echo "$app_details" | cut -d'|' -f3)
            
            cat <<EOF
,
        "version": "$version",
        "status": "$status",
        "size": "$size"
EOF
        fi
        
        echo "      }"
        echo "    }"
    done
    
    echo "  ]"
    echo "}"
}

# Estatísticas
show_statistics() {
    local scopes_data="$1"
    
    if [ -z "$scopes_data" ]; then
        return 1
    fi
    
    local total_scopes=$(echo "$scopes_data" | wc -l)
    local unique_modules=$(echo "$scopes_data" | cut -d'|' -f1 | sort -u | wc -l)
    local unique_apps=$(echo "$scopes_data" | cut -d'|' -f2 | sort -u | wc -l)
    local unique_users=$(echo "$scopes_data" | cut -d'|' -f3 | sort -u | wc -l)
    local active_modules=$(echo "$scopes_data" | grep "|1|" | cut -d'|' -f1 | sort -u | wc -l)
    
    # Apps instalados
    local installed_apps=0
    local missing_apps=0
    echo "$scopes_data" | cut -d'|' -f2 | sort -u | while read -r app; do
        if pm list packages | grep -q "package:$app"; then
            echo "installed"
        else
            echo "missing"
        fi
    done > /tmp/app_status_$$.tmp
    
    installed_apps=$(grep -c "installed" /tmp/app_status_$$.tmp 2>/dev/null || echo "0")
    missing_apps=$(grep -c "missing" /tmp/app_status_$$.tmp 2>/dev/null || echo "0")
    rm -f /tmp/app_status_$$.tmp
    
    echo
    log INFO "📊 Estatísticas dos escopos:"
    echo "    Total de configurações: $total_scopes"
    echo "    Módulos únicos: $unique_modules ($active_modules ativos)"
    echo "    Apps únicos: $unique_apps ($installed_apps instalados, $missing_apps ausentes)"
    echo "    Usuários únicos: $unique_users"
    
    # Top apps mais usados
    echo
    echo "    Apps mais usados como escopo:"
    echo "$scopes_data" | cut -d'|' -f2 | sort | uniq -c | sort -nr | head -5 | while read -r count app; do
        local status="❌"
        if pm list packages | grep -q "package:$app"; then
            status="📱"
        fi
        printf "        %s %-3d %s\n" "$status" "$count" "$app"
    done
}

# Detectar problemas
detect_scope_issues() {
    local scopes_data="$1"
    local issues=""
    
    # Apps não instalados
    local missing_count=$(echo "$scopes_data" | cut -d'|' -f2 | sort -u | while read -r app; do
        if ! pm list packages | grep -q "package:$app"; then
            echo "1"
        fi
    done | wc -l)
    
    if [ "$missing_count" -gt 0 ]; then
        issues="${issues}    • $missing_count app(s) de escopo não instalado(s)\n"
    fi
    
    # Escopos de módulos desabilitados
    local inactive_scopes=$(echo "$scopes_data" | grep "|0|" | wc -l)
    if [ "$inactive_scopes" -gt 0 ]; then
        issues="${issues}    • $inactive_scopes escopo(s) de módulos desabilitados\n"
    fi
    
    # Escopos duplicados (mesmo app, mesmo user, módulos diferentes)
    local duplicates=$(echo "$scopes_data" | awk -F'|' '{print $2 "|" $3}' | sort | uniq -d | wc -l)
    if [ "$duplicates" -gt 0 ]; then
        issues="${issues}    • $duplicates escopo(s) potencialmente conflitantes\n"
    fi
    
    if [ -n "$issues" ]; then
        echo
        log WARN "⚠️  Problemas detectados:"
        echo -e "$issues"
        echo "Use --details para análise mais profunda"
    fi
}

# Main
main() {
    init_environment
    parse_args "$@"
    
    log INFO "🎯 Listando escopos aplicados..."
    
    # Construir e executar query
    local query=$(build_query)
    local raw_scopes=$(sqlite3 "$DB" "$query" 2>/dev/null)
    
    if [ -z "$raw_scopes" ]; then
        log WARN "Nenhum escopo encontrado"
        exit 0
    fi
    
    # Aplicar filtro de apps instalados
    local scopes_data=$(filter_installed_only "$raw_scopes")
    
    if [ -z "$scopes_data" ]; then
        log WARN "Nenhum escopo encontrado após aplicar filtros"
        exit 0
    fi
    
    # Saída no formato solicitado
    case "$OUTPUT_FORMAT" in
        table) format_table "$scopes_data" ;;
        list) format_list "$scopes_data" ;;
        minimal) format_minimal "$scopes_data" ;;
        json) format_json "$scopes_data" ;;
        *) log ERROR "Formato inválido: $OUTPUT_FORMAT"; exit 1 ;;
    esac
    
    # Informações adicionais apenas para formato tabela
    if [ "$OUTPUT_FORMAT" = "table" ]; then
        show_statistics "$scopes_data"
        detect_scope_issues "$scopes_data"
    fi
}

main "$@"