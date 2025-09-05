# LSPosed CLI Tools

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Android](https://img.shields.io/badge/Android-5.0%2B-green.svg)](https://android.com)
[![LSPosed](https://img.shields.io/badge/LSPosed-Compatible-blue.svg)](https://github.com/LSPosed/LSPosed)
[![Shell](https://img.shields.io/badge/Shell-POSIX-orange.svg)](https://en.wikipedia.org/wiki/POSIX)

**Advanced command-line tools for managing LSPosed modules with intelligent scope discovery, automatic backup, and batch operations.**

---

## 🚀 **Key Features**

- 🔧 **Complete Management**: Enable, disable, and configure modules via CLI
- 🎯 **Intelligent Discovery**: Automatic scope discovery and suggestion system
- 📱 **App Exploration**: List and categorize all available system packages
- 💾 **Robust Backup**: Backup/restore system with versioning and integrity checks
- ⚡ **Batch Operations**: Process multiple modules simultaneously
- 👥 **Multi-user**: Full support for Work Profiles and secondary users
- 🛡️ **Rigorous Validation**: Integrity checks and automatic health checks
- 📊 **Rich Interface**: Formatted tables, colors, and detailed information
- 🔍 **Preview Mode**: Dry-run to visualize changes before applying

---

## 📋 **Requirements**

### **System**
- ✅ Android 5.0+ (API 21+)
- ✅ Root access (Magisk recommended)
- ✅ LSPosed Framework installed and working
- ✅ BusyBox or ROM with complete binaries (`sqlite3`, `awk`, `sed`)

### **Connectivity**
- ✅ ADB enabled for remote installation
- ✅ Shell access (su) for local execution

### **Compatibility**
- ✅ Magisk 20.0+
- ✅ LSPosed v1.8.0+
- ✅ POSIX shell compatible

---

## 🛠️ **Installation**

### **Method 1: Automatic Installation (Recommended)**

```bash
# Download and install via curl
curl -fsSL https://raw.githubusercontent.com/rogy153/ScopeForge---LSPosed-CLI-Manager/main/install.sh | adb shell su -c 'sh'

# Or via wget
wget -qO- https://raw.githubusercontent.com/rogy153/ScopeForge---LSPosed-CLI-Manager/main/install.sh | adb shell su -c 'sh'
```

### **Method 2: Manual Installation**

```bash
# 1. Clone the repository
git clone https://github.com/rogy153/ScopeForge---LSPosed-CLI-Manager.git
cd ScopeForge---LSPosed-CLI-Manager

# 2. Push scripts to device
adb push scripts/ /data/local/tmp/lsposed-cli/

# 3. Install on device
adb shell su -c '/data/local/tmp/lsposed-cli/install.sh'

# 4. Load aliases (optional, but recommended)
adb shell su -c 'source /data/local/tmp/lsposed-cli/aliases.sh'
```

### **Installation Verification**

```bash
# Check system health
adb shell su -c 'lsp-health'

# Expected output:
✅ Root: OK
✅ LSPosed: Database found
✅ LSPosed Database: Integrity OK
✅ LSPosed Tables: OK
✅ SQLite3: 3.32.2
✅ Free space: 2048MB
📊 Active modules: 3
📊 Configured scopes: 12
🎉 Validation completed: System OK
```

---

## 📚 **Usage Guide**

### **Essential Commands**

| Command | Description | Example |
|---------|-------------|---------|
| `lsp-health` | Complete system diagnosis | `lsp-health` |
| `lsp-list` | List installed modules | `lsp-list --enabled` |
| `lsp-available` | Explore system packages | `lsp-available --search nfc` |
| `lsp-discover` | Discover scopes for module | `lsp-discover com.module.example` |
| `lsp-enable` | Enable module with scopes | `lsp-enable --auto com.module.example` |
| `lsp-disable` | Disable module | `lsp-disable com.module.example` |
| `lsp-scopes` | List applied scopes | `lsp-scopes --module com.module.example` |
| `lsp-backup` | Manage backups | `lsp-backup --create "snapshot"` |
| `lsp-bulk` | Batch operations | `lsp-bulk --enable module1 module2` |

### **Typical Workflow**

```bash
# 1. Check system
lsp-health

# 2. List available modules
lsp-list

# 3. Explore apps for scopes
lsp-available --category system

# 4. Discover recommended scopes
lsp-discover de.tu_darmstadt.seemoo.nfcgate

# 5. Preview configuration
lsp-enable --dry-run --auto de.tu_darmstadt.seemoo.nfcgate

# 6. Apply configuration
lsp-enable --auto de.tu_darmstadt.seemoo.nfcgate

# 7. Verify result
lsp-scopes --module de.tu_darmstadt.seemoo.nfcgate

# 8. Reboot to apply
adb shell su -c 'svc power reboot'
```

---

## 🎯 **Practical Examples**

### **Basic Module Configuration**

```bash
# Enable NFCGate with automatic discovery
lsp-enable --auto de.tu_darmstadt.seemoo.nfcgate

# Result:
📦 Module: de.tu_darmstadt.seemoo.nfcgate (mid=2)
🎯 Applied scopes:
    - com.android.nfc
    - com.samsung.android.nfc
    - com.android.systemui
💾 Backup created: modules_config_20250905_143022.db
✅ Configuration completed!
```

### **Interactive Configuration**

```bash
# Visual selection mode
lsp-enable --choose de.tu_darmstadt.seemoo.nfcgate

# Interface:
┌─────┬────────────────────────────┬──────────────┬────────────┐
│ ID  │ Package                    │ Type         │ Status     │
├─────┼────────────────────────────┼──────────────┼────────────┤
│ [1] │ com.android.nfc           │ System       │ Installed  │
│ [2] │ com.samsung.android.nfc   │ Vendor       │ Installed  │
│ [3] │ com.android.systemui      │ System       │ Installed  │
│ [4] │ com.android.settings      │ System       │ Installed  │
└─────┴────────────────────────────┴──────────────┴────────────┘

Selection ([a]ll, [n]one, numbers): 1,2,3
Multi-user? [y/N]: y
User IDs (0,10): 0,10
```

### **Package Exploration**

```bash
# Find all NFC-related apps
lsp-available --search nfc --with-sizes

# Details of a specific package
lsp-available --details com.android.systemui

# Apps by category
lsp-available --category google --format json
```

### **Batch Operations**

```bash
# Create module list
cat > /sdcard/modules.txt <<EOF
de.tu_darmstadt.seemoo.nfcgate
com.ceco.pie.gravitybox
tk.wasdennnoch.androidn_ify
EOF

# Enable all automatically
lsp-bulk --enable --scope-mode auto --file /sdcard/modules.txt

# Preview batch operation
lsp-bulk --enable --dry-run --file /sdcard/modules.txt
```

### **Backup Management**

```bash
# Create backup with tag
lsp-backup --create "before_nfc_configuration"

# List backups
lsp-backup --list

# Restore specific backup
lsp-backup --restore 3

# Automatic cleanup
lsp-backup --cleanup --keep 10
```

---

## 📖 **Script Documentation**

### **Main Scripts**

| Script | Function | Documentation |
|--------|----------|---------------|
| [`enable_module.sh`](docs/enable_module.md) | Enable modules with scopes | [📖 Docs](docs/enable_module.md) |
| [`disable_module.sh`](docs/disable_module.md) | Disable modules | [📖 Docs](docs/disable_module.md) |
| [`list_modules.sh`](docs/list_modules.md) | List installed modules | [📖 Docs](docs/list_modules.md) |
| [`list_scopes.sh`](docs/list_scopes.md) | List applied scopes | [📖 Docs](docs/list_scopes.md) |
| [`list_scopes_available.sh`](docs/list_scopes_available.md) | Explore available packages | [📖 Docs](docs/list_scopes_available.md) |
| [`discover_scopes.sh`](docs/discover_scopes.md) | Intelligently discover scopes | [📖 Docs](docs/discover_scopes.md) |
| [`health_check.sh`](docs/health_check.md) | System diagnosis | [📖 Docs](docs/health_check.md) |
| [`manage_backups.sh`](docs/manage_backups.md) | Manage backups | [📖 Docs](docs/manage_backups.md) |
| [`bulk_operations.sh`](docs/bulk_operations.md) | Batch operations | [📖 Docs](docs/bulk_operations.md) |

### **Configuration Files**

| File | Purpose | Location |
|------|---------|----------|
| `scopes_manifest.yml` | Scope definitions per module | `scripts/data/` |
| `popular_modules.yml` | Known modules database | `scripts/data/` |
| `aliases.sh` | Aliases for easier usage | `scripts/` |
| `config.sh` | System configurations | `scripts/` |

---

## 🔧 **Advanced Configuration**

### **Customizing the Scope Manifest**

Edit `scripts/data/scopes_manifest.yml` to add your own modules:

```yaml
modules:
  your.custom.module:
    description: "Description of your module"
    defaults:
      - com.android.systemui
      - android
    patterns:
      - '^com\.android\.settings$'
      - 'launcher'
```

### **Global Settings**

Edit `scripts/config.sh`:

```bash
# Default configurations
export AUTO_BACKUP=true
export CACHE_DURATION=3600
export LOG_LEVEL=INFO
export DEFAULT_USER_ID=0
```

### **Custom Aliases**

Add your own aliases in `scripts/aliases.sh`:

```bash
# Your custom aliases
alias lsp-status='lsp-list && echo && lsp-scopes'
alias lsp-find='lsp-available --search'
alias lsp-safe-enable='lsp-backup --create "auto" && lsp-enable'
```

---

## 🐛 **Troubleshooting**

### **Common Issues**

#### **❌ "LSPosed Tables: Not found"**
```bash
# Check if LSPosed is working
adb shell su -c 'pgrep lspd'
adb shell su -c 'sqlite3 /data/adb/lspd/config/modules_config.db ".tables"'

# If empty, reboot device
adb shell su -c 'reboot'
```

#### **❌ "sqlite3: command not found"**
```bash
# Install BusyBox via Magisk Manager
# Or use ROM with complete binaries
```

#### **❌ "Permission denied"**
```bash
# Check root and permissions
adb shell su -c 'whoami'  # should return 'root'
adb shell su -c 'ls -la /data/adb/lspd/'
```

#### **❌ Scripts don't execute**
```bash
# Check execution permissions
adb shell su -c 'chmod +x /data/local/tmp/lsposed-cli/*.sh'
adb shell su -c 'chmod +x /data/local/tmp/lsposed-cli/core/*.sh'
```

### **Logs and Debug**

```bash
# View system logs
lsp-health

# Detailed logs
adb shell su -c 'cat /data/local/tmp/lsposed-cli/logs/$(date +%Y%m%d).log'

# Debug specific script
adb shell su -c 'sh -x /data/local/tmp/lsposed-cli/enable_module.sh --help'
```

### **Complete Reset**

```bash
# Safety backup
lsp-backup --create "before_reset"

# Total reset
lsp-bulk --disable --force $(lsp-list --enabled --format minimal)
lsp-bulk --cleanup --force

# Check system
lsp-health
```

---

## 🤝 **Contributing**

Contributions are welcome! Please:

1. **Fork** the repository
2. Create a **branch** for your feature (`git checkout -b feature/new-functionality`)
3. **Commit** your changes (`git commit -am 'Add new functionality'`)
4. **Push** to the branch (`git push origin feature/new-functionality`)
5. Open a **Pull Request**

### **Contribution Guidelines**

- ✅ Maintain POSIX shell compatibility
- ✅ Add tests for new features
- ✅ Document changes in README
- ✅ Follow existing logging pattern
- ✅ Test on multiple Android versions

### **Reporting Bugs**

Use the [issue tracker](https://github.com/rogy153/ScopeForge---LSPosed-CLI-Manager/issues) and include:

- 📱 Android version
- 🔧 LSPosed version
- 📋 Complete error logs
- 🔄 Steps to reproduce

---

## 📜 **License**

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

```
MIT License

Copyright (c) 2025 LSPosed CLI Tools

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 🙏 **Acknowledgments**

- **[LSPosed Team](https://github.com/LSPosed/LSPosed)** - Main framework
- **[Magisk](https://github.com/topjohnwu/Magisk)** - Root module system
- **[BusyBox](https://busybox.net/)** - Essential Unix utilities
- **Xposed Community** - Inspiration and support

---

## 📈 **Project Status**

- ✅ **Stable**: Core functionality tested and working
- 🔄 **Active**: Continuous development and regular maintenance
- 📊 **Coverage**: 90%+ of use cases covered
- 🌍 **Compatibility**: Android 5.0+ and LSPosed 1.8.0+

---

## 🔗 **Useful Links**

- 📖 [Complete Documentation](docs/)
- 🎯 [Examples Guide](EXAMPLES_GUIDE.md)
- 🐛 [Issues](https://github.com/rogy153/scopeforger/issues)
- 💬 [Discussions](https://github.com/rogy153/scopeforger/discussions)
- 📋 [Changelog](CHANGELOG.md)
- 🚀 [Releases](https://github.com/rogy153/scopeforger/releases)

### **Emergency Links** 🚨
*For when the GUI is down and you need help fast:*
- 🆘 [Quick Recovery Guide](docs/emergency-recovery.md)
- 🔧 [Common GUI Problems](docs/gui-troubleshooting.md)
- ⚡ [One-Liner Commands](docs/quick-commands.md)

---

<div align="center">

**⭐ If this project was helpful, consider giving it a star!**

[![Star History Chart](https://api.star-history.com/svg?repos=rogy153/ScopeForge---LSPosed-CLI-Manager&type=Date)](https://star-history.com/#rogy153/ScopeForge---LSPosed-CLI-Manager&Date)

</div>

---

<div align="center">
<sub>Developed with ❤️ for the Android community</sub>
</div>








# LSPosed CLI Tools

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Android](https://img.shields.io/badge/Android-5.0%2B-green.svg)](https://android.com)
[![LSPosed](https://img.shields.io/badge/LSPosed-Compatible-blue.svg)](https://github.com/LSPosed/LSPosed)
[![Shell](https://img.shields.io/badge/Shell-POSIX-orange.svg)](https://en.wikipedia.org/wiki/POSIX)

**Ferramentas avançadas de linha de comando para gerenciar módulos LSPosed com descoberta inteligente de escopos, backup automático e operações em lote.**

---

## 🚀 **Características Principais**

- 🔧 **Gerenciamento Completo**: Habilitar, desabilitar e configurar módulos via CLI
- 🎯 **Descoberta Inteligente**: Sistema automático de descoberta e sugestão de escopos
- 📱 **Exploração de Apps**: Lista e categoriza todos os packages disponíveis no sistema
- 💾 **Backup Robusto**: Sistema de backup/restore com versionamento e integridade
- ⚡ **Operações em Lote**: Processar múltiplos módulos simultaneamente
- 👥 **Multi-usuário**: Suporte completo a Work Profiles e usuários secundários
- 🛡️ **Validação Rigorosa**: Verificações de integridade e health checks automáticos
- 📊 **Interface Rica**: Tabelas formatadas, cores e informações detalhadas
- 🔍 **Modo Preview**: Dry-run para visualizar mudanças antes de aplicar

---

## 📋 **Requisitos**

### **Sistema**
- ✅ Android 5.0+ (API 21+)
- ✅ Root access (Magisk recomendado)
- ✅ LSPosed Framework instalado e funcionando
- ✅ BusyBox ou ROM com binários completos (`sqlite3`, `awk`, `sed`)

### **Conectividade**
- ✅ ADB habilitado para instalação remota
- ✅ Acesso via shell (su) para execução local

### **Compatibilidade**
- ✅ Magisk 20.0+
- ✅ LSPosed v1.8.0+
- ✅ POSIX shell compatible

---

## 🛠️ **Instalação**

### **Método 1: Instalação Automática (Recomendado)**

```bash
# Download e instalação via curl
curl -fsSL https://raw.githubusercontent.com/rogy153/ScopeForge---LSPosed-CLI-Manager/main/install.sh | adb shell su -c 'sh'

# Ou via wget
wget -qO- https://raw.githubusercontent.com/rogy153/ScopeForge---LSPosed-CLI-Manager/main/install.sh | adb shell su -c 'sh'
```

### **Método 2: Instalação Manual**

```bash
# 1. Clone o repositório
git clone https://github.com/rogy153/ScopeForge---LSPosed-CLI-Manager.git
cd ScopeForge---LSPosed-CLI-Manager

# 2. Enviar scripts para o dispositivo
adb push scripts/ /data/local/tmp/lsposed-cli/

# 3. Instalar no dispositivo
adb shell su -c '/data/local/tmp/lsposed-cli/install.sh'

# 4. Carregar aliases (opcional, mas recomendado)
adb shell su -c 'source /data/local/tmp/lsposed-cli/aliases.sh'
```

### **Verificação da Instalação**

```bash
# Verificar saúde do sistema
adb shell su -c 'lsp-health'

# Saída esperada:
✅ Root: OK
✅ LSPosed: Banco encontrado
✅ Banco LSPosed: Integridade OK
✅ Tabelas LSPosed: OK
✅ SQLite3: 3.32.2
✅ Espaço livre: 2048MB
📊 Módulos ativos: 3
📊 Escopos configurados: 12
🎉 Validação concluída: Sistema OK
```

---

## 📚 **Guia de Uso**

### **Comandos Essenciais**

| Comando | Descrição | Exemplo |
|---------|-----------|---------|
| `lsp-health` | Diagnóstico completo do sistema | `lsp-health` |
| `lsp-list` | Listar módulos instalados | `lsp-list --enabled` |
| `lsp-available` | Explorar packages do sistema | `lsp-available --search nfc` |
| `lsp-discover` | Descobrir escopos para módulo | `lsp-discover com.module.example` |
| `lsp-enable` | Habilitar módulo com escopos | `lsp-enable --auto com.module.example` |
| `lsp-disable` | Desabilitar módulo | `lsp-disable com.module.example` |
| `lsp-scopes` | Listar escopos aplicados | `lsp-scopes --module com.module.example` |
| `lsp-backup` | Gerenciar backups | `lsp-backup --create "snapshot"` |
| `lsp-bulk` | Operações em lote | `lsp-bulk --enable module1 module2` |

### **Fluxo de Trabalho Típico**

```bash
# 1. Verificar sistema
lsp-health

# 2. Listar módulos disponíveis
lsp-list

# 3. Explorar apps para escopos
lsp-available --category system

# 4. Descobrir escopos recomendados
lsp-discover de.tu_darmstadt.seemoo.nfcgate

# 5. Preview da configuração
lsp-enable --dry-run --auto de.tu_darmstadt.seemoo.nfcgate

# 6. Aplicar configuração
lsp-enable --auto de.tu_darmstadt.seemoo.nfcgate

# 7. Verificar resultado
lsp-scopes --module de.tu_darmstadt.seemoo.nfcgate

# 8. Reiniciar para aplicar
adb shell su -c 'svc power reboot'
```

---

## 🎯 **Exemplos Práticos**

### **Configuração Básica de Módulo**

```bash
# Habilitar NFCGate com descoberta automática
lsp-enable --auto de.tu_darmstadt.seemoo.nfcgate

# Resultado:
📦 Módulo: de.tu_darmstadt.seemoo.nfcgate (mid=2)
🎯 Escopos aplicados:
    - com.android.nfc
    - com.samsung.android.nfc
    - com.android.systemui
💾 Backup criado: modules_config_20250905_143022.db
✅ Configuração concluída!
```

### **Configuração Interativa**

```bash
# Modo de seleção visual
lsp-enable --choose de.tu_darmstadt.seemoo.nfcgate

# Interface:
┌─────┬────────────────────────────┬──────────────┬────────────┐
│ ID  │ Package                    │ Tipo         │ Status     │
├─────┼────────────────────────────┼──────────────┼────────────┤
│ [1] │ com.android.nfc           │ Sistema      │ Instalado  │
│ [2] │ com.samsung.android.nfc   │ Vendor       │ Instalado  │
│ [3] │ com.android.systemui      │ Sistema      │ Instalado  │
│ [4] │ com.android.settings      │ Sistema      │ Instalado  │
└─────┴────────────────────────────┴──────────────┴────────────┘

Seleção ([a]ll, [n]one, números): 1,2,3
Multi-usuário? [y/N]: y
User IDs (0,10): 0,10
```

### **Exploração de Packages**

```bash
# Encontrar todos os apps relacionados a NFC
lsp-available --search nfc --with-sizes

# Detalhes de um package específico
lsp-available --details com.android.systemui

# Apps por categoria
lsp-available --category google --format json
```

### **Operações em Lote**

```bash
# Criar lista de módulos
cat > /sdcard/modules.txt <<EOF
de.tu_darmstadt.seemoo.nfcgate
com.ceco.pie.gravitybox
tk.wasdennnoch.androidn_ify
EOF

# Habilitar todos automaticamente
lsp-bulk --enable --scope-mode auto --file /sdcard/modules.txt

# Preview de operação em lote
lsp-bulk --enable --dry-run --file /sdcard/modules.txt
```

### **Gerenciamento de Backups**

```bash
# Criar backup com tag
lsp-backup --create "antes_configuracao_nfc"

# Listar backups
lsp-backup --list

# Restaurar backup específico
lsp-backup --restore 3

# Limpeza automática
lsp-backup --cleanup --keep 10
```

---

## 📖 **Documentação dos Scripts**

### **Scripts Principais**

| Script | Função | Documentação |
|--------|--------|--------------|
| [`enable_module.sh`](docs/enable_module.md) | Habilitar módulos com escopos | [📖 Docs](docs/enable_module.md) |
| [`disable_module.sh`](docs/disable_module.md) | Desabilitar módulos | [📖 Docs](docs/disable_module.md) |
| [`list_modules.sh`](docs/list_modules.md) | Listar módulos instalados | [📖 Docs](docs/list_modules.md) |
| [`list_scopes.sh`](docs/list_scopes.md) | Listar escopos aplicados | [📖 Docs](docs/list_scopes.md) |
| [`list_scopes_available.sh`](docs/list_scopes_available.md) | Explorar packages disponíveis | [📖 Docs](docs/list_scopes_available.md) |
| [`discover_scopes.sh`](docs/discover_scopes.md) | Descobrir escopos inteligentemente | [📖 Docs](docs/discover_scopes.md) |
| [`health_check.sh`](docs/health_check.md) | Diagnóstico do sistema | [📖 Docs](docs/health_check.md) |
| [`manage_backups.sh`](docs/manage_backups.md) | Gerenciar backups | [📖 Docs](docs/manage_backups.md) |
| [`bulk_operations.sh`](docs/bulk_operations.md) | Operações em lote | [📖 Docs](docs/bulk_operations.md) |

### **Arquivos de Configuração**

| Arquivo | Propósito | Localização |
|---------|-----------|-------------|
| `scopes_manifest.yml` | Definições de escopos por módulo | `scripts/data/` |
| `popular_modules.yml` | Banco de módulos conhecidos | `scripts/data/` |
| `aliases.sh` | Aliases para facilitar uso | `scripts/` |
| `config.sh` | Configurações do sistema | `scripts/` |

---

## 🔧 **Configuração Avançada**

### **Personalizando o Manifesto de Escopos**

Edite `scripts/data/scopes_manifest.yml` para adicionar seus próprios módulos:

```yaml
modules:
  seu.modulo.personalizado:
    description: "Descrição do seu módulo"
    defaults:
      - com.android.systemui
      - android
    patterns:
      - '^com\.android\.settings$'
      - 'launcher'
```

### **Configurações Globais**

Edite `scripts/config.sh`:

```bash
# Configurações padrão
export AUTO_BACKUP=true
export CACHE_DURATION=3600
export LOG_LEVEL=INFO
export DEFAULT_USER_ID=0
```

### **Aliases Personalizados**

Adicione seus próprios aliases em `scripts/aliases.sh`:

```bash
# Seus aliases personalizados
alias lsp-status='lsp-list && echo && lsp-scopes'
alias lsp-find='lsp-available --search'
alias lsp-safe-enable='lsp-backup --create "auto" && lsp-enable'
```

---

## 🐛 **Troubleshooting**

### **Problemas Comuns**

#### **❌ "Tabelas LSPosed: Não encontradas"**
```bash
# Verificar se LSPosed está funcionando
adb shell su -c 'pgrep lspd'
adb shell su -c 'sqlite3 /data/adb/lspd/config/modules_config.db ".tables"'

# Se vazio, reiniciar dispositivo
adb shell su -c 'reboot'
```

#### **❌ "sqlite3: command not found"**
```bash
# Instalar BusyBox via Magisk Manager
# Ou usar ROM com binários completos
```

#### **❌ "Permission denied"**
```bash
# Verificar root e permissões
adb shell su -c 'whoami'  # deve retornar 'root'
adb shell su -c 'ls -la /data/adb/lspd/'
```

#### **❌ Scripts não executam**
```bash
# Verificar permissões de execução
adb shell su -c 'chmod +x /data/local/tmp/lsposed-cli/*.sh'
adb shell su -c 'chmod +x /data/local/tmp/lsposed-cli/core/*.sh'
```

### **Logs e Debug**

```bash
# Ver logs do sistema
lsp-health

# Logs detalhados
adb shell su -c 'cat /data/local/tmp/lsposed-cli/logs/$(date +%Y%m%d).log'

# Debug de script específico
adb shell su -c 'sh -x /data/local/tmp/lsposed-cli/enable_module.sh --help'
```

### **Reset Completo**

```bash
# Backup de segurança
lsp-backup --create "before_reset"

# Reset total
lsp-bulk --disable --force $(lsp-list --enabled --format minimal)
lsp-bulk --cleanup --force

# Verificar sistema
lsp-health
```

---

## 🤝 **Contribuição**

Contribuições são bem-vindas! Por favor:

1. **Fork** o repositório
2. Crie uma **branch** para sua feature (`git checkout -b feature/nova-funcionalidade`)
3. **Commit** suas mudanças (`git commit -am 'Adiciona nova funcionalidade'`)
4. **Push** para a branch (`git push origin feature/nova-funcionalidade`)
5. Abra um **Pull Request**

### **Diretrizes de Contribuição**

- ✅ Mantenha compatibilidade POSIX shell
- ✅ Adicione testes para novas funcionalidades
- ✅ Documente mudanças no README
- ✅ Siga o padrão de logging existente
- ✅ Teste em múltiplas versões do Android

### **Reportando Bugs**

Use o [issue tracker](https://github.com/rogy153/ScopeForge---LSPosed-CLI-Manager/issues) e inclua:

- 📱 Versão do Android
- 🔧 Versão do LSPosed
- 📋 Logs de erro completos
- 🔄 Passos para reproduzir

---

## 📜 **Licença**

Este projeto está licenciado sob a Licença MIT - veja o arquivo [LICENSE](LICENSE) para detalhes.

```
MIT License

Copyright (c) 2025 LSPosed CLI Tools

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 🙏 **Agradecimentos**

- **[LSPosed Team](https://github.com/LSPosed/LSPosed)** - Framework principal
- **[Magisk](https://github.com/topjohnwu/Magisk)** - Sistema de módulos root
- **[BusyBox](https://busybox.net/)** - Utilitários Unix essenciais
- **Comunidade Xposed** - Inspiração e suporte

---

## 📈 **Status do Projeto**

- ✅ **Estável**: Core functionality testada e funcionando
- 🔄 **Ativo**: Desenvolvimento contínuo e manutenção regular
- 📊 **Cobertura**: 90%+ dos casos de uso cobertos
- 🌍 **Compatibilidade**: Android 5.0+ e LSPosed 1.8.0+

---

## 🔗 **Links Úteis**

- 📖 [Documentação Completa](docs/)
- 🎯 [Guia de Exemplos](EXAMPLES_GUIDE.md)
- 🐛 [Issues](https://github.com/rogy153/scopeforger/issues)
- 💬 [Discussions](https://github.com/rogy153/scopeforger/discussions)
- 📋 [Changelog](CHANGELOG.md)
- 🚀 [Releases](https://github.com/rogy153/scopeforger/releases)

### **Emergency Links** 🚨
*For when the GUI is down and you need help fast:*
- 🆘 [Quick Recovery Guide](docs/emergency-recovery.md)
- 🔧 [Common GUI Problems](docs/gui-troubleshooting.md)
- ⚡ [One-Liner Commands](docs/quick-commands.md)

---

<div align="center">

**⭐ Se este projeto foi útil, considere dar uma estrela!**

[![Star History Chart](https://api.star-history.com/svg?repos=rogy153/ScopeForge---LSPosed-CLI-Manager&type=Date)](https://star-history.com/#rogy153/ScopeForge---LSPosed-CLI-Manager&Date)

</div>

---

<div align="center">
<sub>Desenvolvido com ❤️ para a comunidade Android</sub>
</div>
