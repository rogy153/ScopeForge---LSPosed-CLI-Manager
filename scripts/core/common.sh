#!/system/bin/sh
# Funções compartilhadas e configurações globais

set -e

# Configurações
DB="/data/adb/lspd/config/modules_config.db"
BACKUP_DIR="/data/local/tmp/lsposed-cli/backups"
CACHE_DIR="/data/local/tmp/lsposed-cli/cache"
LOG_FILE="/data/local/tmp/lsposed-cli/logs/$(date +%Y%m%d).log"
MANIFEST="/data/local/tmp/lsposed-cli/data/scopes_manifest.yml"
POPULAR_MODULES="/data/local/tmp/lsposed-cli/data/popular_modules.yml"

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Logging
log() {
    local level="$1"
    shift
    local msg="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $msg" >> "$LOG_FILE"
    
    case "$level" in
        ERROR) echo -e "${RED}❌ $msg${NC}" >&2 ;;
        WARN)  echo -e "${YELLOW}⚠️  $msg${NC}" >&2 ;;
        INFO)  echo -e "${GREEN}ℹ️  $msg${NC}" ;;
        DEBUG) [ -n "$DEBUG" ] && echo -e "${CYAN}🔍 $msg${NC}" ;;
        *) echo "$msg" ;;
    esac
}

# Verificações básicas
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log ERROR "Root necessário. Execute com: su -c 'script'"
        exit 1
    fi
}

check_lspd() {
    if [ ! -f "$DB" ]; then
        log ERROR "LSPosed não encontrado. Banco: $DB"
        exit 1
    fi
    
    if ! sqlite3 "$DB" ".tables" >/dev/null 2>&1; then
        log ERROR "Banco LSPosed corrompido ou inacessível"
        exit 1
    fi
}

# Cache de packages instalados
get_installed_packages() {
    local cache_file="$CACHE_DIR/packages_$(date +%Y%m%d_%H).cache"
    
    if [ -f "$cache_file" ] && [ $(($(date +%s) - $(stat -c %Y "$cache_file"))) -lt 3600 ]; then
        cat "$cache_file"
    else
        mkdir -p "$CACHE_DIR"
        pm list packages | sed 's/^package://g' | tee "$cache_file"
    fi
}

# Validação de package
validate_package() {
    local pkg="$1"
    if ! echo "$pkg" | grep -qE '^[a-zA-Z0-9._]+$'; then
        log ERROR "Nome de package inválido: $pkg"
        return 1
    fi
    return 0
}

# Backup automático
create_auto_backup() {
    local tag="${1:-auto}"
    local backup_name="modules_config_$(date +%Y%m%d_%H%M%S).db"
    local backup_path="$BACKUP_DIR/$backup_name"
    
    mkdir -p "$BACKUP_DIR"
    cp "$DB" "$backup_path"
    
    # Metadata
    cat > "${backup_path}.meta" <<EOF
timestamp=$(date +%s)
tag=$tag
size=$(stat -c %s "$backup_path")
modules_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM modules;")
scopes_count=$(sqlite3 "$DB" "SELECT COUNT(*) FROM scope;")
EOF
    
    log INFO "Backup criado: $backup_name (tag: $tag)"
    echo "$backup_path"
}

# Formatação de tabelas
print_table() {
    local data="$1"
    local headers="$2"
    
    if command -v column >/dev/null 2>&1; then
        echo "$headers"
        echo "$data" | column -t -s '|'
    else
        echo "$headers"
        echo "$data"
    fi
}

# Verificação de conectividade ADB
check_adb_connection() {
    if ! command -v adb >/dev/null 2>&1; then
        log ERROR "ADB não encontrado no PATH"
        return 1
    fi
    
    if ! adb devices | grep -q "device$"; then
        log ERROR "Nenhum device Android conectado via ADB"
        return 1
    fi
    
    return 0
}

# Inicialização
init_environment() {
    mkdir -p "$(dirname "$LOG_FILE")" "$BACKUP_DIR" "$CACHE_DIR"
    check_root
    check_lspd
    log INFO "Ambiente inicializado com sucesso"
}