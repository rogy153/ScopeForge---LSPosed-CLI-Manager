#!/system/bin/sh
# Descoberta inteligente de escopos para módulos LSPosed

source "$(dirname "$0")/core/common.sh"

# Configurações padrão
USER_ID=0
SHOW_DETAILS=false
OUTPUT_FORMAT="table"
INCLUDE_INSTALLED_ONLY=true

usage() {
    cat <<EOF
uso: $0 <module_pkg_name> [OPÇÕES]

OPÇÕES:
  --user <id>            User ID específico (padrão: 0)
  --details              Mostrar informações detalhadas dos escopos
  --format <tipo>        Formato de saída: table, list, json
  --include-missing      Incluir apps não instalados nas sugestões
  --help                 Mostrar esta ajuda

EXEMPLOS:
  $0 de.tu_darmstadt.seemoo.nfcgate
  $0 --details com.ceco.pie.gravitybox
  $0 --format json de.tu_darmstadt.seemoo.nfcgate
  $0 --include-missing tk.wasdennnoch.androidn_ify
EOF
    exit 1
}

# Parse argumentos
parse_args() {
    [ -z "$1" ] && usage
    MODULE_PKG="$1"; shift
    
    while [ -n "$1" ]; do
        case "$1" in
            --user) USER_ID="$2"; shift 2 ;;
            --details) SHOW_DETAILS=true; shift ;;
            --format) OUTPUT_FORMAT="$2"; shift 2 ;;
            --include-missing) INCLUDE_INSTALLED_ONLY=false; shift ;;
            --help) usage ;;
            -*) log ERROR "Opção desconhecida: $1"; usage ;;
            *) log ERROR "Argumento inválido: $1"; usage ;;
        esac
    done
}

# Extrair configuração do manifesto
extract_manifest_config() {
    local pkg="$1"
    
    if [ ! -f "$MANIFEST" ]; then
        return 1
    fi
    
    # Extrair defaults
    awk -v pkg="$pkg" '
        $0 ~ "^\\s*" pkg ":\\s*$" {inmod=1; next}
        inmod && $0 ~ /^\\s*[^#[:space:]]+:\\s*$/ && $0 !~ "^\\s*" pkg ":\\s*$" {inmod=0}
        inmod && $0 ~ /^\\s*defaults:\\s*$/ {inlist=1; next}
        inlist && $0 ~ /^\\s*-/ {gsub(/^\\s*-\\s*/, "", $0); if($0) print "default|" $0; next}
        inlist && $0 !~ /^\\s*-/ {inlist=0}
    ' "$MANIFEST"
    
    # Extrair patterns
    awk -v pkg="$pkg" '
        $0 ~ "^\\s*" pkg ":\\s*$" {inmod=1; next}
        inmod && $0 ~ /^\\s*[^#[:space:]]+:\\s*$/ && $0 !~ "^\\s*" pkg ":\\s*$" {inmod=0}
        inmod && $0 ~ /^\\s*patterns:\\s*$/ {inlist=1; next}
        inlist && $0 ~ /^\\s*-/ {gsub(/^\\s*-\\s*/, "", $0); gsub(/'\''/, "", $0); if($0) print "pattern|" $0; next}
        inlist && $0 !~ /^\\s*-/ {inlist=0}
    ' "$MANIFEST"
}

# Aplicar patterns sobre packages instalados
apply_patterns() {
    local patterns="$1"
    local packages="$2"
    
    echo "$patterns" | while IFS='|' read -r type pattern; do
        [ "$type" = "pattern" ] && [ -n "$pattern" ] || continue
        echo "$packages" | grep -iE "$pattern" | while read -r pkg; do
            echo "pattern|$pkg|$pattern"
        done
    done
}

# Categorizar escopo
categorize_scope() {
    local pkg="$1"
    
    case "$pkg" in
        android) echo "core" ;;
        com.android.systemui) echo "system" ;;
        com.android.settings) echo "system" ;;
        com.android.phone) echo "system" ;;
        com.android.dialer) echo "system" ;;
        com.android.contacts) echo "system" ;;
        com.android.camera*) echo "camera" ;;
        com.android.nfc) echo "nfc" ;;
        com.android.*) echo "system" ;;
        com.google.*) echo "google" ;;
        com.samsung.*|com.sec.*) echo "samsung" ;;
        com.xiaomi.*|com.miui.*) echo "xiaomi" ;;
        com.huawei.*|com.hihonor.*) echo "huawei" ;;
        *launcher*) echo "launcher" ;;
        *nfc*) echo "nfc" ;;
        *camera*) echo "camera" ;;
        *) echo "user" ;;
    esac
}

# Verificar se app está instalado
is_app_installed() {
    local pkg="$1"
    get_installed_packages | grep -qx "$pkg"
}

# Obter informações do app
get_app_info() {
    local pkg="$1"
    local version="N/A"
    local size="N/A"
    local enabled="unknown"
    
    if is_app_installed "$pkg"; then
        enabled="installed"
        version=$(dumpsys package "$pkg" 2>/dev/null | grep -E "versionName=" | head -1 | cut -d'=' -f2 | tr -d ' ')
        
        if $SHOW_DETAILS; then
            local apk_path=$(pm path "$pkg" 2>/dev/null | head -1 | cut -d':' -f2)
            if [ -n "$apk_path" ] && [ -f "$apk_path" ]; then
                size=$(stat -c %s "$apk_path" 2>/dev/null | awk '{printf "%.1fMB", $1/1024/1024}')
            fi
        fi
    else
        enabled="missing"
    fi
    
    echo "$pkg|$(categorize_scope "$pkg")|$version|$enabled|$size"
}

# Descobrir escopos
discover_scopes() {
    local module_pkg="$1"
    
    log INFO "🔍 Descobrindo escopos para: $module_pkg"
    
    # Verificar se módulo existe
    if ! sqlite3 "$DB" "SELECT 1 FROM modules WHERE module_pkg_name='$module_pkg';" >/dev/null 2>&1; then
        log ERROR "Módulo não encontrado no LSPosed: $module_pkg"
        return 1
    fi
    
    # Extrair configuração do manifesto
    local manifest_config=$(extract_manifest_config "$module_pkg")
    
    if [ -z "$manifest_config" ]; then
        log WARN "Módulo não encontrado no manifesto, usando descoberta genérica"
        # Fallback para padrões genéricos
        manifest_config="default|com.android.systemui
default|android"
    fi
    
    # Obter packages instalados
    local installed_packages=$(get_installed_packages)
    
    # Processar defaults
    local suggestions=""
    echo "$manifest_config" | while IFS='|' read -r type value; do
        case "$type" in
            default)
                if $INCLUDE_INSTALLED_ONLY; then
                    if is_app_installed "$value"; then
                        echo "default|$value"
                    fi
                else
                    echo "default|$value"
                fi
                ;;
        esac
    done > /tmp/defaults_$$.tmp
    
    # Processar patterns
    local patterns=$(echo "$manifest_config" | grep "^pattern|")
    apply_patterns "$patterns" "$installed_packages" > /tmp/patterns_$$.tmp
    
    # Combinar e remover duplicatas
    cat /tmp/defaults_$$.tmp /tmp/patterns_$$.tmp 2>/dev/null | sort -u -t'|' -k2 > /tmp/all_suggestions_$$.tmp
    
    # Limpar arquivos temporários
    rm -f /tmp/defaults_$$.tmp /tmp/patterns_$$.tmp
    
    cat /tmp/all_suggestions_$$.tmp
    rm -f /tmp/all_suggestions_$$.tmp
}

# Formato tabela
format_table() {
    local suggestions="$1"
    
    if [ -z "$suggestions" ]; then
        log WARN "Nenhum escopo sugerido"
        return 1
    fi
    
    echo
    if $SHOW_DETAILS; then
        printf "┌─────┬─────────────────────────────────┬──────────┬─────────┬─────────┬─────────┬────────────┐\n"
        printf "│ %-3s │ %-31s │ %-8s │ %-7s │ %-7s │ %-7s │ %-10s │\n" "ID" "Package" "Categoria" "Origem" "Versão" "Tamanho" "Status"
        printf "├─────┼─────────────────────────────────┼──────────┼─────────┼─────────┼─────────┼────────────┤\n"
    else
        printf "┌─────┬─────────────────────────────────┬──────────┬─────────┬────────────┐\n"
        printf "│ %-3s │ %-31s │ %-8s │ %-7s │ %-10s │\n" "ID" "Package" "Categoria" "Origem" "Status"
        printf "├─────┼─────────────────────────────────┼──────────┼─────────┼────────────┤\n"
    fi
    
    local id=1
    echo "$suggestions" | while IFS='|' read -r origin pkg pattern; do
        local app_info=$(get_app_info "$pkg")
        local category=$(echo "$app_info" | cut -d'|' -f2)
        local version=$(echo "$app_info" | cut -d'|' -f3)
        local status=$(echo "$app_info" | cut -d'|' -f4)
        local size=$(echo "$app_info" | cut -d'|' -f5)
        
        # Truncar package se muito longo
        local short_pkg="$pkg"
        if [ ${#pkg} -gt 31 ]; then
            short_pkg="$(echo "$pkg" | cut -c1-28)..."
        fi
        
        # Colorir status
        local status_display="$status"
        case "$status" in
            installed) status_display="✅ OK" ;;
            missing) status_display="❌ Missing" ;;
        esac
        
        if $SHOW_DETAILS; then
            printf "│ [%-1d] │ %-31s │ %-8s │ %-7s │ %-7s │ %-7s │ %-10s │\n" \
                "$id" "$short_pkg" "$category" "$origin" "$version" "$size" "$status_display"
        else
            printf "│ [%-1d] │ %-31s │ %-8s │ %-7s │ %-10s │\n" \
                "$id" "$short_pkg" "$category" "$origin" "$status_display"
        fi
        
        id=$((id + 1))
    done
    
    if $SHOW_DETAILS; then
        printf "└─────┴─────────────────────────────────┴──────────┴─────────┴─────────┴─────────┴────────────┘\n"
    else
        printf "└─────┴─────────────────────────────────┴──────────┴─────────┴────────────┘\n"
    fi
}

# Formato lista
format_list() {
    local suggestions="$1"
    
    echo "$suggestions" | while IFS='|' read -r origin pkg pattern; do
        local status="❌"
        if is_app_installed "$pkg"; then
            status="✅"
        fi
        echo "$status $pkg ($origin)"
    done
}

# Formato JSON
format_json() {
    local suggestions="$1"
    
    echo "{"
    echo "  \"module\": \"$MODULE_PKG\","
    echo "  \"user_id\": $USER_ID,"
    echo "  \"suggestions\": ["
    
    local first=true
    echo "$suggestions" | while IFS='|' read -r origin pkg pattern; do
        local app_info=$(get_app_info "$pkg")
        local category=$(echo "$app_info" | cut -d'|' -f2)
        local version=$(echo "$app_info" | cut -d'|' -f3)
        local status=$(echo "$app_info" | cut -d'|' -f4)
        local size=$(echo "$app_info" | cut -d'|' -f5)
        
        if $first; then
            first=false
        else
            echo ","
        fi
        
        cat <<EOF
    {
      "package": "$pkg",
      "category": "$category",
      "origin": "$origin",
      "version": "$version",
      "status": "$status",
      "size": "$size",
      "pattern": "${pattern:-null}"
    }
EOF
    done
    
    echo "  ]"
    echo "}"
}

# Mostrar estatísticas
show_statistics() {
    local suggestions="$1"
    
    if [ -z "$suggestions" ]; then
        return 1
    fi
    
    local total=$(echo "$suggestions" | wc -l)
    local installed=$(echo "$suggestions" | while IFS='|' read -r origin pkg pattern; do
        if is_app_installed "$pkg"; then echo "1"; fi
    done | wc -l)
    local missing=$((total - installed))
    
    local defaults=$(echo "$suggestions" | grep "^default|" | wc -l)
    local patterns=$(echo "$suggestions" | grep "^pattern|" | wc -l)
    
    echo
    log INFO "📊 Estatísticas da descoberta:"
    echo "    Total de sugestões: $total"
    echo "    Apps instalados: $installed"
    echo "    Apps não instalados: $missing"
    echo "    Origem - Defaults: $defaults"
    echo "    Origem - Patterns: $patterns"
    
    # Verificar se módulo já tem escopos
    local current_scopes=$(sqlite3 "$DB" "
        SELECT COUNT(s.app_pkg_name)
        FROM scope s
        JOIN modules m ON s.mid = m.mid
        WHERE m.module_pkg_name='$MODULE_PKG' AND s.user_id=$USER_ID
    " 2>/dev/null)
    
    if [ "$current_scopes" -gt 0 ]; then
        echo "    Escopos já aplicados: $current_scopes"
    fi
}

# Verificar conflitos
check_conflicts() {
    local suggestions="$1"
    local module_pkg="$2"
    
    # Verificar se algum escopo sugerido já está sendo usado por outro módulo
    echo "$suggestions" | while IFS='|' read -r origin pkg pattern; do
        local conflicts=$(sqlite3 "$DB" "
            SELECT m.module_pkg_name
            FROM scope s
            JOIN modules m ON s.mid = m.mid
            WHERE s.app_pkg_name='$pkg' 
            AND s.user_id=$USER_ID 
            AND m.module_pkg_name != '$module_pkg'
        " 2>/dev/null)
        
        if [ -n "$conflicts" ]; then
            echo "⚠️  $pkg já usado por: $conflicts"
        fi
    done
}

# Main
main() {
    init_environment
    parse_args "$@"
    
    # Descobrir escopos
    local suggestions=$(discover_scopes "$MODULE_PKG")
    
    if [ -z "$suggestions" ]; then
        log ERROR "Nenhum escopo descoberto para $MODULE_PKG"
        exit 1
    fi
    
    # Mostrar resultado no formato solicitado
    case "$OUTPUT_FORMAT" in
        table) format_table "$suggestions" ;;
        list) format_list "$suggestions" ;;
        json) format_json "$suggestions" ;;
        *) log ERROR "Formato inválido: $OUTPUT_FORMAT"; exit 1 ;;
    esac
    
    # Informações adicionais apenas para formato tabela
    if [ "$OUTPUT_FORMAT" = "table" ]; then
        show_statistics "$suggestions"
        
        echo
        log INFO "⚡ Próximos passos:"
        echo "    1. Revisar sugestões acima"
        echo "    2. Habilitar com: enable_module.sh --auto $MODULE_PKG"
        echo "    3. Ou modo interativo: enable_module.sh --choose $MODULE_PKG"
        
        # Verificar conflitos
        local conflicts=$(check_conflicts "$suggestions" "$MODULE_PKG")
        if [ -n "$conflicts" ]; then
            echo
            log WARN "Possíveis conflitos detectados:"
            echo "$conflicts"
        fi
    fi
}

main "$@"