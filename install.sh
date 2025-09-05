#!/system/bin/sh
# Instalador automático do LSPosed CLI Tools

set -e

INSTALL_DIR="/data/local/tmp/lsposed-cli"
REPO_URL="https://github.com/seu-repo/lsposed-cli-tools"

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    local level="$1"
    shift
    case "$level" in
        ERROR) echo -e "${RED}❌ $*${NC}" >&2 ;;
        WARN)  echo -e "${YELLOW}⚠️  $*${NC}" >&2 ;;
        INFO)  echo -e "${GREEN}ℹ️  $*${NC}" ;;
        *) echo "$*" ;;
    esac
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        log ERROR "Root necessário para instalação"
        exit 1
    fi
}

check_dependencies() {
    local missing=""
    local required_cmds="sqlite3 pm awk sed"

    for cmd in $required_cmds; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing="$missing $cmd"
        fi
    done

    if [ -n "$missing" ]; then
        log ERROR "Comandos necessários não encontrados:$missing"
        log INFO "Instale BusyBox ou ROM com binários completos"
        exit 1
    fi
}

create_directory_structure() {
    log INFO "Criando estrutura de diretórios..."

    mkdir -p "$INSTALL_DIR"/{core,data,logs,backups,cache}

    # Permissões adequadas
    chmod 755 "$INSTALL_DIR"
    chmod 700 "$INSTALL_DIR"/{logs,backups,cache}
    chmod 755 "$INSTALL_DIR"/{core,data}
}

install_local() {
    log INFO "Instalando localmente..."

    create_directory_structure

    # Copiar scripts (assumindo que estamos no diretório do projeto)
    if [ -d "scripts" ]; then
        cp -r scripts/* "$INSTALL_DIR/"
    else
        log ERROR "Diretório 'scripts' não encontrado"
        exit 1
    fi

    # Permissões
    find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;

    setup_aliases
}

install_remote() {
    log INFO "Baixando do repositório..."

    create_directory_structure

    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$REPO_URL/archive/main.tar.gz" | tar -xz -C /tmp
    elif command -v wget >/dev/null 2>&1; then
        wget -qO- "$REPO_URL/archive/main.tar.gz" | tar -xz -C /tmp
    else
        log ERROR "curl ou wget necessário para instalação remota"
        exit 1
    fi

    # Copiar arquivos
    if [ -d "/tmp/lsposed-cli-tools-main/scripts" ]; then
        cp -r /tmp/lsposed-cli-tools-main/scripts/* "$INSTALL_DIR/"
        rm -rf /tmp/lsposed-cli-tools-main
    else
        log ERROR "Estrutura do repositório inválida"
        exit 1
    fi

    # Permissões
    find "$INSTALL_DIR" -name "*.sh" -exec chmod +x {} \;

    setup_aliases
}

setup_aliases() {
    log INFO "Configurando aliases..."

    cat > "$INSTALL_DIR/aliases.sh" <<'EOF'
#!/system/bin/sh
# Aliases para facilitar uso dos LSPosed CLI Tools

# Comandos principais
alias lsp-enable='/data/local/tmp/lsposed-cli/enable_module.sh'
alias lsp-disable='/data/local/tmp/lsposed-cli/disable_module.sh'
alias lsp-list='/data/local/tmp/lsposed-cli/list_modules.sh'
alias lsp-scopes='/data/local/tmp/lsposed-cli/list_scopes.sh'
alias lsp-available='/data/local/tmp/lsposed-cli/list_scopes_available.sh'
alias lsp-discover='/data/local/tmp/lsposed-cli/discover_scopes.sh'
alias lsp-health='/data/local/tmp/lsposed-cli/health_check.sh'
alias lsp-backup='/data/local/tmp/lsposed-cli/manage_backups.sh'
alias lsp-bulk='/data/local/tmp/lsposed-cli/bulk_operations.sh'

# Atalhos úteis
alias lsp-status='lsp-list && echo && lsp-scopes'
alias lsp-check='lsp-health'
alias lsp-find='lsp-available --search'

# Função helper
lsp-help() {
    echo "LSPosed CLI Tools - Comandos disponíveis:"
    echo
    echo "📦 MÓDULOS:"
    echo "  lsp-enable    - Habilitar módulo com escopos"
    echo "  lsp-disable   - Desabilitar módulo"
    echo "  lsp-list      - Listar módulos instalados"
    echo "  lsp-bulk      - Operações em lote"
    echo
    echo "🎯 ESCOPOS:"
    echo "  lsp-scopes    - Listar escopos aplicados"
    echo "  lsp-available - Listar todos os packages disponíveis"
    echo "  lsp-discover  - Descobrir escopos para módulo"
    echo "  lsp-find      - Buscar packages (alias para lsp-available --search)"
    echo
    echo "🔧 SISTEMA:"
    echo "  lsp-health    - Diagnóstico completo"
    echo "  lsp-backup    - Gerenciar backups"
    echo "  lsp-status    - Status geral (módulos + escopos)"
    echo
    echo "Use <comando> --help para ajuda específica"
}

echo "✅ LSPosed CLI Tools carregado!"
echo "Use 'lsp-help' para ver todos os comandos"
EOF

    chmod +x "$INSTALL_DIR/aliases.sh"
}

create_config_file() {
    log INFO "Criando arquivo de configuração..."

    cat > "$INSTALL_DIR/config.sh" <<EOF
#!/system/bin/sh
# Configuração do LSPosed CLI Tools

# Caminhos
export LSPOSED_CLI_DIR="$INSTALL_DIR"
export LSPOSED_DB="/data/adb/lspd/config/modules_config.db"

# Configurações padrão
export AUTO_BACKUP=true
export CACHE_DURATION=3600
export LOG_LEVEL=INFO
export DEFAULT_USER_ID=0

# Carregamento automático
if [ -f "\$LSPOSED_CLI_DIR/aliases.sh" ]; then
    source "\$LSPOSED_CLI_DIR/aliases.sh"
fi
EOF

    chmod +x "$INSTALL_DIR/config.sh"
}

setup_systemd_path() {
    # Adicionar ao PATH do sistema (se possível)
    local profile_files="/system/etc/profile /system/etc/bash.bashrc"

    for profile in $profile_files; do
        if [ -w "$profile" ]; then
            if ! grep -q "lsposed-cli" "$profile"; then
                echo "# LSPosed CLI Tools" >> "$profile"
                echo "export PATH=\"$INSTALL_DIR:\$PATH\"" >> "$profile"
                log INFO "Adicionado ao PATH em $profile"
            fi
        fi
    done
}

run_initial_check() {
    log INFO "Executando verificação inicial..."

    if [ -f "$INSTALL_DIR/health_check.sh" ]; then
        "$INSTALL_DIR/health_check.sh" || {
            log WARN "Verificação inicial detectou problemas"
            log INFO "Execute 'lsp-health' para diagnóstico completo"
        }
    fi
}

show_usage_instructions() {
    echo
    log INFO "🎉 Instalação concluída!"
    echo
    echo "📋 PRÓXIMOS PASSOS:"
    echo
    echo "1. Carregar aliases (uma vez por sessão):"
    echo "   source $INSTALL_DIR/aliases.sh"
    echo
    echo "2. Ou adicionar ao seu perfil permanentemente:"
    echo "   echo 'source $INSTALL_DIR/aliases.sh' >> ~/.bashrc"
    echo
    echo "3. Verificar saúde do sistema:"
    echo "   lsp-health"
    echo
    echo "4. Listar módulos disponíveis:"
    echo "   lsp-list"
    echo
    echo "5. Exemplo de uso completo:"
    echo "   lsp-discover de.tu_darmstadt.seemoo.nfcgate"
    echo "   lsp-enable --auto de.tu_darmstadt.seemoo.nfcgate"
    echo
    echo "📚 Para ajuda:"
    echo "   lsp-help"
    echo "   <comando> --help"
    echo
}

main() {
    echo "🚀 LSPosed CLI Tools - Instalador Automático"
    echo "=============================================="
    echo

    check_root
    check_dependencies

    log INFO "Diretório de instalação: $INSTALL_DIR"

    # Backup da instalação anterior
    if [ -d "$INSTALL_DIR" ]; then
        local backup_dir="${INSTALL_DIR}.backup.$(date +%Y%m%d_%H%M%S)"
        log INFO "Fazendo backup da instalação anterior..."
        cp -r "$INSTALL_DIR" "$backup_dir"
        log INFO "Backup salvo em: $backup_dir"
    fi

    # Instalação
    if [ -d "scripts" ]; then
        install_local
    else
        install_remote
    fi

    create_config_file
    setup_systemd_path
    run_initial_check
    show_usage_instructions
}

main "$@"
