#!/system/bin/sh
# Lista módulos LSPosed com filtros e informações detalhadas

source "$(dirname "$0")/core/common.sh"

# Configurações padrão
FILTER_STATUS="all"
SHOW_SCOPES=false
SHOW_DETAILS=false
OUTPUT_FORMAT="table"
SORT_BY="name"

usage() {
    cat <<EOF
uso: $0 [OPÇÕES]

FILTROS:
  --enabled              Apenas módulos habilitados
  --disabled             Apenas módulos desabilitados
  --with-scopes          Apenas módulos com escopos configurados
  --without-scopes       Apenas módulos sem escopos
  --broken               Apenas módulos com problemas (APK inexistente)

INFORMAÇÕES:
  --show-scopes          Mostrar escopos de cada módulo
  --details              Informações detalhadas (versão, tamanho, etc.)
  --sort <campo>         Ordenar por: name, status, scopes, size

FORMATOS:
  --format <tipo>        Saída: table, list, json, minimal

EXEMPLOS:
  $0 --enabled --show-scopes
  $0 --details --sort scopes
  $0 --broken
  $0 --format json --enabled
EOF
    exit 1
}

# Parse argumentos
parse_args() {
    while [ -n "$1" ]; do
        case "$1" in
            --enabled) FILTER_STATUS="enabled"; shift ;;
            --disabled) FILTER_STATUS="disabled"; shift ;;
            --with-scopes) FILTER_STATUS="with_scopes"; shift ;;
            --without-scopes) FILTER_STATUS="without_scopes"; shift ;;
            --broken) FILTER_STATUS="broken"; shift ;;
            --show-scopes) SHOW_SCOPES=true; shift ;;
            --details) SHOW_DETAILS=true; shift ;;
            --sort) SORT_BY="$2"; shift 2 ;;
            --format) OUTPUT_FORMAT="$2"; shift 2 ;;
            --help) usage ;;
            -*) log ERROR "Opção desconhecida: $1"; usage ;;
            *) log ERROR "Argumento inválido: $1"; usage ;;
        esac
    done
}

# Obter informações de um módulo
get_module_info() {
    local mid="$1"
    local pkg="$2"
    local apk_path="$3"
    local enabled="$4"
    
    # Informações básicas
    local version="N/A"
    local size="N/A"
    local apk_exists="true"
    local scopes_count=0
    local users_count=0
    
    # Verificar se APK existe
    if [ -n "$apk_path" ] && [ ! -f "$apk_path" ]; then
        apk_exists="false"
    fi
    
    # Contar escopos
    scopes_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM scope WHERE mid=$mid;" 2>/dev/null || echo "0")
    users_count=$(sqlite3 "$DB" "SELECT COUNT(DISTINCT user_id) FROM scope WHERE mid=$mid;" 2>/dev/null || echo "0")
    
    # Informações detalhadas se solicitado
    if $SHOW_DETAILS && [ "$apk_exists" = "true" ] && [ -n "$apk_path" ]; then
        # Tentar obter versão do dumpsys
        version=$(dumpsys package "$pkg" 2>/dev/null | grep -E "versionName=" | head -1 | cut -d'=' -f2 | tr -d ' ')
        
        # Tamanho do APK
        if [ -f "$apk_path" ]; then
            size=$(stat -c %s "$apk_path" 2>/dev/null | awk '{printf "%.1fMB", $1/1024/1024}')
        fi
    fi
    
    echo "$mid|$pkg|$apk_path|$enabled|$version|$size|$apk_exists|$scopes_count|$users_count"
}

# Obter lista de escopos de um módulo
get_module_scopes() {
    local mid="$1"
    
    sqlite3 "$DB" "
        SELECT app_pkg_name, user_id 
        FROM scope 
        WHERE mid=$mid 
        ORDER BY user_id, app_pkg_name
    " 2>/dev/null | while IFS='|' read -r app_pkg user_id; do
        echo "    [u$user_id] $app_pkg"
    done
}

# Aplicar filtros
apply_filters() {
    local modules_data="$1"
    
    case "$FILTER_STATUS" in
        all) echo "$modules_data" ;;
        enabled) echo "$modules_data" | grep "|1|" ;;
        disabled) echo "$modules_data" | grep "|0|" ;;
        with_scopes) echo "$modules_data" | awk -F'|' '$8 > 0' ;;
        without_scopes) echo "$modules_data" | awk -F'|' '$8 == 0' ;;
        broken) echo "$modules_data" | grep "|false|" ;;
        *) echo "$modules_data" ;;
    esac
}

# Ordenar resultados
sort_results() {
    local modules_data="$1"
    
    case "$SORT_BY" in
        name) echo "$modules_data" | sort -t'|' -k2 ;;
        status) echo "$modules_data" | sort -t'|' -k4 -r ;;
        scopes) echo "$modules_data" | sort -t'|' -k8 -n -r ;;
        size) echo "$modules_data" | sort -t'|' -k6 ;;
        *) echo "$modules_data" | sort -t'|' -k2 ;;
    esac
}

# Formato tabela
format_table() {
    local modules_data="$1"
    
    if [ -z "$modules_data" ]; then
        log WARN "Nenhum módulo encontrado com os filtros aplicados"
        return 1
    fi
    
    echo
    if $SHOW_DETAILS; then
        printf "┌─────┬─────────────────────────────────┬─────────┬─────────┬─────────┬─────────┬─────────┐\n"
        printf "│ %-3s │ %-31s │ %-7s │ %-7s │ %-7s │ %-7s │ %-7s │\n" "MID" "Package" "Status" "Versão" "Tamanho" "Escopos" "Usuários"
        printf "├─────┼─────────────────────────────────┼─────────┼─────────┼─────────┼─────────┼─────────┤\n"
    else
        printf "┌─────┬─────────────────────────────────┬─────────┬─────────┬─────────┐\n"
        printf "│ %-3s │ %-31s │ %-7s │ %-7s │ %-7s │\n" "MID" "Package" "Status" "Escopos" "Usuários"
        printf "├─────┼─────────────────────────────────┼─────────┼─────────┼─────────┤\n"
    fi
    
    echo "$modules_data" | while IFS='|' read -r mid pkg apk_path enabled version size apk_exists scopes_count users_count; do
        # Truncar package se muito longo
        local short_pkg="$pkg"
        if [ ${#pkg} -gt 31 ]; then
            short_pkg="$(echo "$pkg" | cut -c1-28)..."
        fi
        
        # Status com ícones
        local status_display=""
        if [ "$enabled" = "1" ]; then
            if [ "$apk_exists" = "true" ]; then
                status_display="✅ ON"
            else
                status_display="⚠️  ON*"
            fi
        else
            status_display="⭕ OFF"
        fi
        
        if $SHOW_DETAILS; then
            printf "│ %-3s │ %-31s │ %-7s │ %-7s │ %-7s │ %-7s │ %-7s │\n" \
                "$mid" "$short_pkg" "$status_display" "$version" "$size" "$scopes_count" "$users_count"
        else
            printf "│ %-3s │ %-31s │ %-7s │ %-7s │ %-7s │\n" \
                "$mid" "$short_pkg" "$status_display" "$scopes_count" "$users_count"
        fi
        
        # Mostrar escopos se solicitado
        if $SHOW_SCOPES && [ "$scopes_count" -gt 0 ]; then
            printf "│     │ Escopos:                        │         │         │         │\n"
            get_module_scopes "$mid" | while read -r scope_line; do
                printf "│     │ %-31s │         │         │         │\n" "$scope_line"
            done
        fi
    done
    
    if $SHOW_DETAILS; then
        printf "└─────┴─────────────────────────────────┴─────────┴─────────┴─────────┴─────────┴─────────┘\n"
    else
        printf "└─────┴─────────────────────────────────┴─────────┴─────────┴─────────┘\n"
    fi
    
    if $SHOW_DETAILS; then
        echo
        echo "Legenda: ✅=Ativo ⭕=Inativo ⚠️=Ativo mas APK inexistente"
    fi
}

# Formato lista
format_list() {
    local modules_data="$1"
    
    echo "$modules_data" | while IFS='|' read -r mid pkg apk_path enabled version size apk_exists scopes_count users_count; do
        local status_icon="⭕"
        [ "$enabled" = "1" ] && status_icon="✅"
        [ "$enabled" = "1" ] && [ "$apk_exists" = "false" ] && status_icon="⚠️"
        
        echo "$status_icon $pkg (mid=$mid, ${scopes_count} escopos)"
        
        if $SHOW_SCOPES && [ "$scopes_count" -gt 0 ]; then
            get_module_scopes "$mid" | sed 's/^/  /'
        fi
    done
}

# Formato minimal
format_minimal() {
    local modules_data="$1"
    
    echo "$modules_data" | while IFS='|' read -r mid pkg apk_path enabled version size apk_exists scopes_count users_count; do
        echo "$pkg"
    done
}

# Formato JSON
format_json() {
    local modules_data="$1"
    
    echo "{"
    echo "  \"timestamp\": \"$(date -Iseconds)\","
    echo "  \"filter\": \"$FILTER_STATUS\","
    echo "  \"modules\": ["
    
    local first=true
    echo "$modules_data" | while IFS='|' read -r mid pkg apk_path enabled version size apk_exists scopes_count users_count; do
        if $first; then
            first=false
        else
            echo ","
        fi
        
        cat <<EOF
    {
      "mid": $mid,
      "package": "$pkg",
      "apk_path": "$apk_path",
      "enabled": $([ "$enabled" = "1" ] && echo "true" || echo "false"),
      "version": "$version",
      "size": "$size",
      "apk_exists": $([ "$apk_exists" = "true" ] && echo "true" || echo "false"),
      "scopes_count": $scopes_count,
      "users_count": $users_count
EOF
        
        if $SHOW_SCOPES && [ "$scopes_count" -gt 0 ]; then
            echo ","
            echo "      \"scopes\": ["
            local scope_first=true
            get_module_scopes "$mid" | while read -r scope_line; do
                local user_id=$(echo "$scope_line" | grep -oE '\[u[0-9]+\]' | grep -oE '[0-9]+')
                local app_pkg=$(echo "$scope_line" | sed 's/.*] //')
                
                if $scope_first; then
                    scope_first=false
                else
                    echo ","
                fi
                
                echo "        {\"app_package\": \"$app_pkg\", \"user_id\": $user_id}"
            done
            echo "      ]"
        fi
        
        echo "    }"
    done
    
    echo "  ]"
    echo "}"
}

# Estatísticas gerais
show_statistics() {
    local modules_data="$1"
    
    if [ -z "$modules_data" ]; then
        return 1
    fi
    
    local total=$(echo "$modules_data" | wc -l)
    local enabled=$(echo "$modules_data" | grep "|1|" | wc -l)
    local disabled=$(echo "$modules_data" | grep "|0|" | wc -l)
    local with_scopes=$(echo "$modules_data" | awk -F'|' '$8 > 0' | wc -l)
    local broken=$(echo "$modules_data" | grep "|false|" | wc -l)
    
    local total_scopes=$(echo "$modules_data" | awk -F'|' '{sum+=$8} END {print sum+0}')
    
    echo
    log INFO "📊 Estatísticas dos módulos:"
    echo "    Total: $total módulos"
    echo "    Habilitados: $enabled"
    echo "    Desabilitados: $disabled"
    echo "    Com escopos: $with_scopes"
    echo "    Total de escopos: $total_scopes"
    
    if [ "$broken" -gt 0 ]; then
        echo "    ⚠️  Com problemas: $broken"
    fi
}

# Detectar problemas
detect_issues() {
    local modules_data="$1"
    local issues=""
    
    # Módulos com APK inexistente
    local broken_apks=$(echo "$modules_data" | grep "|false|" | wc -l)
    if [ "$broken_apks" -gt 0 ]; then
        issues="${issues}    • $broken_apks módulo(s) com APK inexistente\n"
    fi
    
    # Módulos habilitados sem escopos
    local no_scopes=$(echo "$modules_data" | grep "|1|" | awk -F'|' '$8 == 0' | wc -l)
    if [ "$no_scopes" -gt 0 ]; then
        issues="${issues}    • $no_scopes módulo(s) habilitado(s) sem escopos\n"
    fi
    
    # Módulos desabilitados com escopos
    local orphaned_scopes=$(echo "$modules_data" | grep "|0|" | awk -F'|' '$8 > 0' | wc -l)
    if [ "$orphaned_scopes" -gt 0 ]; then
        issues="${issues}    • $orphaned_scopes módulo(s) desabilitado(s) com escopos órfãos\n"
    fi
    
    if [ -n "$issues" ]; then
        echo
        log WARN "⚠️  Problemas detectados:"
        echo -e "$issues"
        echo "Execute health_check.sh para análise detalhada"
    fi
}

# Main
main() {
    init_environment
    parse_args "$@"
    
    log INFO "📦 Listando módulos LSPosed..."
    
    # Obter dados dos módulos
    local raw_modules=$(sqlite3 "$DB" "SELECT mid, module_pkg_name, apk_path, enabled FROM modules ORDER BY mid;" 2>/dev/null)
    
    if [ -z "$raw_modules" ]; then
        log ERROR "Nenhum módulo encontrado ou erro no banco"
        exit 1
    fi
    
    # Processar informações detalhadas
    local modules_data=""
    echo "$raw_modules" | while IFS='|' read -r mid pkg apk_path enabled; do
        get_module_info "$mid" "$pkg" "$apk_path" "$enabled"
    done > /tmp/modules_info_$$.tmp
    
    modules_data=$(cat /tmp/modules_info_$$.tmp)
    rm -f /tmp/modules_info_$$.tmp
    
    # Aplicar filtros e ordenação
    modules_data=$(apply_filters "$modules_data")
    modules_data=$(sort_results "$modules_data")
    
    # Saída no formato solicitado
    case "$OUTPUT_FORMAT" in
        table) format_table "$modules_data" ;;
        list) format_list "$modules_data" ;;
        minimal) format_minimal "$modules_data" ;;
        json) format_json "$modules_data" ;;
        *) log ERROR "Formato inválido: $OUTPUT_FORMAT"; exit 1 ;;
    esac
    
    # Informações adicionais apenas para formato tabela
    if [ "$OUTPUT_FORMAT" = "table" ]; then
        show_statistics "$modules_data"
        detect_issues "$modules_data"
    fi
}

main "$@"