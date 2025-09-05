#!/system/bin/sh
# Lista todos os escopos (packages) disponíveis no sistema

source "$(dirname "$0")/core/common.sh"

# Configurações padrão
CATEGORY="all"
SEARCH_TERM=""
SHOW_DETAILS=false
SHOW_SIZES=false
ONLY_ENABLED=false
OUTPUT_FORMAT="table"
SORT_BY="name"

usage() {
    cat <<EOF
uso: $0 [OPÇÕES] [PACKAGE_NAME]

CATEGORIAS:
  --category <tipo>       Filtrar por categoria:
                         all, system, vendor, user, google,
                         nfc, camera, launcher, social, games

FILTROS:
  --search <termo>        Buscar packages por nome/descrição
  --enabled-only          Apenas apps habilitados/visíveis
  --with-sizes            Incluir tamanhos dos APKs
  --sort <campo>          Ordenar por: name, size, install_date, category

FORMATOS:
  --format <tipo>         Saída: table, list, json, minimal
  --details <package>     Detalhes completos de um package específico

EXEMPLOS:
  $0 --category system
  $0 --search nfc --with-sizes
  $0 --details com.android.systemui
  $0 --category google --format json
  $0 --enabled-only --sort size
EOF
    exit 1
}

# Parse argumentos
parse_args() {
    while [ -n "$1" ]; do
        case "$1" in
            --category) CATEGORY="$2"; shift 2 ;;
            --search) SEARCH_TERM="$2"; shift 2 ;;
            --enabled-only) ONLY_ENABLED=true; shift ;;
            --with-sizes) SHOW_SIZES=true; shift ;;
            --sort) SORT_BY="$2"; shift 2 ;;
            --format) OUTPUT_FORMAT="$2"; shift 2 ;;
            --details) SHOW_DETAILS=true; SEARCH_TERM="$2"; shift 2 ;;
            --help) usage ;;
            -*) log ERROR "Opção desconhecida: $1"; usage ;;
            *) SEARCH_TERM="$1"; shift ;;
        esac
    done
}

# Categorizar package
categorize_package() {
    local pkg="$1"

    case "$pkg" in
        android) echo "core" ;;
        com.android.*) echo "system" ;;
        com.google.*) echo "google" ;;
        com.samsung.*|com.sec.*) echo "samsung" ;;
        com.xiaomi.*|com.miui.*) echo "xiaomi" ;;
        com.huawei.*|com.hihonor.*) echo "huawei" ;;
        com.oppo.*|com.oneplus.*) echo "oppo" ;;
        com.vivo.*) echo "vivo" ;;
        com.lge.*) echo "lg" ;;
        com.sony.*|com.sonymobile.*) echo "sony" ;;
        com.motorola.*) echo "motorola" ;;
        *launcher*) echo "launcher" ;;
        *camera*) echo "camera" ;;
        *nfc*) echo "nfc" ;;
        *facebook*|*instagram*|*whatsapp*|*telegram*|*twitter*) echo "social" ;;
        *game*|*play.games*) echo "games" ;;
        *) echo "user" ;;
    esac
}

# Obter informações detalhadas do package
get_package_info() {
    local pkg="$1"
    local info=""

    # Informações básicas
    local version=$(dumpsys package "$pkg" 2>/dev/null | grep -E "versionName=" | head -1 | cut -d'=' -f2)
    local enabled=$(pm list packages -e | grep -q "package:$pkg" && echo "enabled" || echo "disabled")
    local install_date=$(dumpsys package "$pkg" 2>/dev/null | grep -E "firstInstallTime=" | head -1 | cut -d'=' -f2)

    # Tamanho (se solicitado)
    local size=""
    if $SHOW_SIZES; then
        local apk_path=$(pm path "$pkg" 2>/dev/null | head -1 | cut -d':' -f2)
        if [ -n "$apk_path" ] && [ -f "$apk_path" ]; then
            size=$(stat -c %s "$apk_path" 2>/dev/null | awk '{printf "%.1fMB", $1/1024/1024}')
        else
            size="N/A"
        fi
    fi

    echo "$pkg|$(categorize_package "$pkg")|${version:-N/A}|$enabled|${size:-}|${install_date:-N/A}"
}

# Filtrar por categoria
filter_by_category() {
    local packages="$1"

    case "$CATEGORY" in
        all) echo "$packages" ;;
        system) echo "$packages" | grep "|system|" ;;
        vendor) echo "$packages" | grep -E "\|(samsung|xiaomi|huawei|oppo|vivo|lg|sony|motorola)\|" ;;
        user) echo "$packages" | grep "|user|" ;;
        google) echo "$packages" | grep "|google|" ;;
        core) echo "$packages" | grep "|core|" ;;
        nfc) echo "$packages" | grep "|nfc|" ;;
        camera) echo "$packages" | grep "|camera|" ;;
        launcher) echo "$packages" | grep "|launcher|" ;;
        social) echo "$packages" | grep "|social|" ;;
        games) echo "$packages" | grep "|games|" ;;
        *) log ERROR "Categoria inválida: $CATEGORY"; exit 1 ;;
    esac
}

# Aplicar filtros de busca
apply_search_filter() {
    local packages="$1"

    if [ -n "$SEARCH_TERM" ]; then
        echo "$packages" | grep -i "$SEARCH_TERM"
    else
        echo "$packages"
    fi
}

# Filtrar apenas habilitados
filter_enabled_only() {
    local packages="$1"

    if $ONLY_ENABLED; then
        echo "$packages" | grep "|enabled|"
    else
        echo "$packages"
    fi
}

# Ordenar resultados
sort_results() {
    local packages="$1"

    case "$SORT_BY" in
        name) echo "$packages" | sort ;;
        category) echo "$packages" | sort -t'|' -k2 ;;
        size) echo "$packages" | sort -t'|' -k5 -n ;;
        *) echo "$packages" | sort ;;
    esac
}

# Formato de saída: tabela
format_table() {
    local packages="$1"

    if [ -z "$packages" ]; then
        log WARN "Nenhum package encontrado com os filtros aplicados"
        return 1
    fi

    local header=""
    if $SHOW_SIZES; then
        header="Package|Categoria|Versão|Status|Tamanho|Instalação"
        printf "┌─────────────────────────────────┬──────────┬─────────┬─────────┬─────────┬────────────┐\n"
        printf "│ %-31s │ %-8s │ %-7s │ %-7s │ %-7s │ %-10s │\n" "Package" "Categoria" "Versão" "Status" "Tamanho" "Instalação"
        printf "├─────────────────────────────────┼──────────┼─────────┼─────────┼─────────┼────────────┤\n"
    else
        header="Package|Categoria|Versão|Status"
        printf "┌─────────────────────────────────┬──────────┬─────────┬─────────┐\n"
        printf "│ %-31s │ %-8s │ %-7s │ %-7s │\n" "Package" "Categoria" "Versão" "Status"
        printf "├─────────────────────────────────┼──────────┼─────────┼─────────┤\n"
    fi

    echo "$packages" | while IFS='|' read -r pkg category version enabled size install_date; do
        [ -z "$pkg" ] && continue

        # Truncar package name se muito longo
        local short_pkg="$pkg"
        if [ ${#pkg} -gt 31 ]; then
            short_pkg="$(echo "$pkg" | cut -c1-28)..."
        fi

        if $SHOW_SIZES; then
            printf "│ %-31s │ %-8s │ %-7s │ %-7s │ %-7s │ %-10s │\n" \
                "$short_pkg" "$category" "$version" "$enabled" "$size" "${install_date:-N/A}"
        else
            printf "│ %-31s │ %-8s │ %-7s │ %-7s │\n" \
                "$short_pkg" "$category" "$version" "$enabled"
        fi
    done

    if $SHOW_SIZES; then
        printf "└─────────────────────────────────┴──────────┴─────────┴─────────┴─────────┴────────────┘\n"
    else
        printf "└─────────────────────────────────┴──────────┴─────────┴─────────┘\n"
    fi
}

# Formato de saída: lista simples
format_list() {
    local packages="$1"

    echo "$packages" | while IFS='|' read -r pkg category version enabled size install_date; do
        [ -z "$pkg" ] && continue
        echo "$pkg ($category)"
    done
}

# Formato de saída: minimal
format_minimal() {
    local packages="$1"

    echo "$packages" | while IFS='|' read -r pkg category version enabled size install_date; do
        [ -z "$pkg" ] && continue
        echo "$pkg"
    done
}

# Formato de saída: JSON
format_json() {
    local packages="$1"

    echo "["
    local first=true
    echo "$packages" | while IFS='|' read -r pkg category version enabled size install_date; do
        [ -z "$pkg" ] && continue

        if $first; then
            first=false
        else
            echo ","
        fi

        cat <<EOF
  {
    "package": "$pkg",
    "category": "$category",
    "version": "$version",
    "enabled": $([ "$enabled" = "enabled" ] && echo "true" || echo "false"),
    "size": "${size:-null}",
    "install_date": "${install_date:-null}"
  }
EOF
    done
    echo "]"
}

# Mostrar detalhes completos de um package
show_package_details() {
    local pkg="$1"

    if ! pm list packages | grep -q "package:$pkg"; then
        log ERROR "Package não encontrado: $pkg"
        return 1
    fi

    log INFO "=== DETALHES DO PACKAGE ==="
    echo

    # Informações básicas
    local info=$(get_package_info "$pkg")
    local category=$(echo "$info" | cut -d'|' -f2)
    local version=$(echo "$info" | cut -d'|' -f3)
    local enabled=$(echo "$info" | cut -d'|' -f4)

    echo "📦 Package: $pkg"
    echo "🏷️  Categoria: $category"
    echo "📊 Versão: $version"
    echo "⚡ Status: $enabled"

    # APK path e tamanho
    local apk_path=$(pm path "$pkg" 2>/dev/null | head -1 | cut -d':' -f2)
    if [ -n "$apk_path" ]; then
        echo "📁 APK: $apk_path"
        if [ -f "$apk_path" ]; then
            local size=$(stat -c %s "$apk_path" | awk '{printf "%.2f MB", $1/1024/1024}')
            echo "💾 Tamanho: $size"
        fi
    fi

    # Permissões principais
    echo
    echo "🔐 Permissões principais:"
    dumpsys package "$pkg" 2>/dev/null | grep -E "android\.permission\." | head -5 | while read -r line; do
        local perm=$(echo "$line" | grep -oE "android\.permission\.[A-Z_]+" | head -1)
        [ -n "$perm" ] && echo "    - $perm"
    done

    # Verificar se está sendo usado como escopo
    if [ -f "$DB" ]; then
        echo
        echo "🎯 Uso como escopo:"
        local scopes=$(sqlite3 "$DB" "
            SELECT m.module_pkg_name, s.user_id
            FROM scope s
            JOIN modules m ON s.mid = m.mid
            WHERE s.app_pkg_name='$pkg'
        " 2>/dev/null)

        if [ -n "$scopes" ]; then
            echo "$scopes" | while read -r module_pkg user_id; do
                echo "    - Módulo: $module_pkg (user $user_id)"
            done
        else
            echo "    - Não está sendo usado como escopo"
        fi
    fi

    # Sugestões do manifesto
    if [ -f "$MANIFEST" ]; then
        echo
        echo "💡 Módulos que podem usar este escopo:"
        awk -v pkg="$pkg" '
        /^  [a-zA-Z0-9._]+:/ {
            module = $1
            gsub(/:$/, "", module)
            gsub(/^[ ]*/, "", module)
            inmod = 1
            next
        }
        inmod && /^    defaults:/ {indefaults=1; next}
        inmod && /^    patterns:/ {inpatterns=1; indefaults=0; next}
        inmod && /^  / && !/^    / {inmod=0; indefaults=0; inpatterns=0}
        indefaults && /^      - / {
            gsub(/^      - /, "", $0)
            if ($0 == pkg) print "    - " module " (default)"
        }
        inpatterns && /^      - / {
            gsub(/^      - /, "", $0)
            gsub(/'\''/, "", $0)
            if (pkg ~ $0) print "    - " module " (pattern: " $0 ")"
        }
        ' "$MANIFEST"
    fi
}

# Estatísticas gerais
show_statistics() {
    local packages="$1"

    if [ -z "$packages" ]; then
        return 1
    fi

    local total=$(echo "$packages" | wc -l)
    local enabled=$(echo "$packages" | grep "|enabled|" | wc -l)
    local disabled=$(echo "$packages" | grep "|disabled|" | wc -l)

    echo
    log INFO "📊 Estatísticas:"
    echo "    Total: $total packages"
    echo "    Habilitados: $enabled"
    echo "    Desabilitados: $disabled"

    # Por categoria
    echo
    echo "    Por categoria:"
    echo "$packages" | cut -d'|' -f2 | sort | uniq -c | while read -r count cat; do
        printf "        %-10s: %d\n" "$cat" "$count"
    done
}

# Main
main() {
    init_environment
    parse_args "$@"

    # Modo detalhes
    if $SHOW_DETAILS; then
        show_package_details "$SEARCH_TERM"
        return $?
    fi

    log INFO "🔍 Coletando informações dos packages..."

    # Obter lista base de packages
    local raw_packages=""
    if $ONLY_ENABLED; then
        raw_packages=$(pm list packages -e | sed 's/^package://')
    else
        raw_packages=$(pm list packages | sed 's/^package://')
    fi

    # Processar informações detalhadas
    local detailed_packages=""
    echo "$raw_packages" | while read -r pkg; do
        [ -z "$pkg" ] && continue
        get_package_info "$pkg"
    done > /tmp/packages_info.tmp

    detailed_packages=$(cat /tmp/packages_info.tmp)
    rm -f /tmp/packages_info.tmp

    # Aplicar filtros
    detailed_packages=$(filter_by_category "$detailed_packages")
    detailed_packages=$(apply_search_filter "$detailed_packages")
    detailed_packages=$(filter_enabled_only "$detailed_packages")
    detailed_packages=$(sort_results "$detailed_packages")

    # Saída
    case "$OUTPUT_FORMAT" in
        table) format_table "$detailed_packages" ;;
        list) format_list "$detailed_packages" ;;
        minimal) format_minimal "$detailed_packages" ;;
        json) format_json "$detailed_packages" ;;
        *) log ERROR "Formato inválido: $OUTPUT_FORMAT"; exit 1 ;;
    esac

    # Estatísticas
    if [ "$OUTPUT_FORMAT" = "table" ]; then
        show_statistics "$detailed_packages"
    fi
}

main "$@"
