# LSPosed CLI Tools - Guia de Exemplos Práticos

Este guia apresenta cenários reais de uso do LSPosed CLI Tools com exemplos detalhados.

## 📚 Índice

1. [Primeiros Passos](#primeiros-passos)
2. [Configuração Básica de Módulos](#configuração-básica-de-módulos)
3. [Cenários Avançados](#cenários-avançados)
4. [Manutenção e Troubleshooting](#manutenção-e-troubleshooting)
5. [Automação e Scripts](#automação-e-scripts)

---

## 🚀 Primeiros Passos

### Instalação Inicial

```bash
# 1. Instalar o sistema completo
adb push scripts/ /data/local/tmp/lsposed-cli/
adb shell su -c '/data/local/tmp/lsposed-cli/install.sh'

# 2. Carregar aliases (adicionar ao .bashrc para permanência)
adb shell su -c 'source /data/local/tmp/lsposed-cli/aliases.sh'

# 3. Verificar saúde do sistema
adb shell su -c 'lsp-health'
```

### Primeira Verificação

```bash
# Verificar módulos instalados
adb shell su -c 'lsp-list'

# Output esperado:
┌─────┬─────────────────────────────────┬─────────┬─────────┬─────────┐
│ MID │ Package                         │ Status  │ Escopos │ Usuários│
├─────┼─────────────────────────────────┼─────────┼─────────┼─────────┤
│ 1   │ io.github.lsposed.manager      │ ✅ ON   │ 2       │ 1       │
│ 2   │ de.tu_darmstadt.seemoo.nfcgate │ ⭕ OFF  │ 0       │ 0       │
└─────┴─────────────────────────────────┴─────────┴─────────┴─────────┘
```

---

## ⚙️ Configuração Básica de Módulos

### Caso 1: Habilitar NFCGate com Descoberta Automática

```bash
# 1. Descobrir escopos recomendados
adb shell su -c 'lsp-discover de.tu_darmstadt.seemoo.nfcgate'

# Output:
>>> módulo: de.tu_darmstadt.seemoo.nfcgate (mid=2) user_id=0
>>> escopos sugeridos:
  1) com.android.nfc
  2) com.samsung.android.nfc
  3) com.android.systemui
  4) com.android.settings

# 2. Habilitar automaticamente com todas as sugestões
adb shell su -c 'lsp-enable --auto de.tu_darmstadt.seemoo.nfcgate'

# 3. Verificar aplicação
adb shell su -c 'lsp-scopes --module de.tu_darmstadt.seemoo.nfcgate'
```

### Caso 2: Configuração Manual com Escopos Específicos

```bash
# Habilitar apenas com escopos específicos
adb shell su -c 'lsp-enable de.tu_darmstadt.seemoo.nfcgate com.android.nfc com.android.systemui'

# Verificar resultado
adb shell su -c 'lsp-scopes de.tu_darmstadt.seemoo.nfcgate'
# Output:
de.tu_darmstadt.seemoo.nfcgate|com.android.nfc|0
de.tu_darmstadt.seemoo.nfcgate|com.android.systemui|0
```

### Caso 3: Configuração Interativa

```bash
# Modo interativo com seleção visual
adb shell su -c 'lsp-enable --choose de.tu_darmstadt.seemoo.nfcgate'

# Interface interativa:
┌─────┬────────────────────────────┬──────────────┬────────────┐
│ ID  │ Package                    │ Tipo         │ Status     │
├─────┼────────────────────────────┼──────────────┼────────────┤
│ [1] │ com.android.nfc           │ Sistema      │ Instalado  │
│ [2] │ com.samsung.android.nfc   │ Vendor       │ Instalado  │
│ [3] │ com.android.systemui      │ Sistema      │ Instalado  │
│ [4] │ com.android.settings      │ Sistema      │ Instalado  │
└─────┴────────────────────────────┴──────────────┴────────────┘

Seleção ([a]ll, [n]one, números): 1,2
Multi-usuário? [y/N]: n

>>> Confirmação:
✓ Aplicar escopos [1,2] no usuário [0]
✓ Criar backup automático
✓ Habilitar módulo

Prosseguir? [Y/n]: y
```

---

## 🔧 Cenários Avançados

### Caso 4: Multi-usuário (Work Profile)

```bash
# 1. Verificar usuários disponíveis
adb shell su -c 'pm list users'
# UserInfo{0:Primary:c13} running
# UserInfo{10:Work profile:1030} running

# 2. Habilitar para múltiplos usuários
adb shell su -c 'lsp-enable --choose --multi-user de.tu_darmstadt.seemoo.nfcgate'

# Na interface interativa:
Selecionar usuários (ex: 0,10 ou 0-10): 0,10

# 3. Verificar escopos aplicados
adb shell su -c 'lsp-scopes --module de.tu_darmstadt.seemoo.nfcgate'
# de.tu_darmstadt.seemoo.nfcgate|com.android.nfc|0
# de.tu_darmstadt.seemoo.nfcgate|com.android.nfc|10
```

### Caso 5: Preview com Dry-Run

```bash
# Preview completo antes de aplicar
adb shell su -c 'lsp-enable --dry-run --auto de.tu_darmstadt.seemoo.nfcgate'

# Output:
>>> [DRY-RUN] Simulando ações para: de.tu_darmstadt.seemoo.nfcgate
📦 Módulo encontrado: mid=2, status=disabled
🎯 Escopos a serem aplicados:
  [1] com.android.nfc (sistema NFC principal)
  [2] com.samsung.android.nfc (vendor Samsung)
  [3] com.android.systemui (interface do sistema)
💾 Backup seria criado: modules_config_20250905_143022.db
⚡ Reinicialização necessária após aplicação
```

### Caso 6: Operações em Lote

```bash
# 1. Criar arquivo com lista de módulos
cat > /sdcard/modules_to_enable.txt <<EOF
# Módulos essenciais
de.tu_darmstadt.seemoo.nfcgate
com.ceco.pie.gravitybox
tk.wasdennnoch.androidn_ify

# Módulo com escopos específicos
io.github.lsposed.manager:com.android.systemui,android
EOF

# 2. Habilitar todos em lote
adb shell su -c 'lsp-bulk --enable --scope-mode auto --file /sdcard/modules_to_enable.txt'

# 3. Preview da operação
adb shell su -c 'lsp-bulk --enable --dry-run --file /sdcard/modules_to_enable.txt'
```

---

## 🔍 Exploração e Descoberta

### Caso 7: Explorar Apps Disponíveis como Escopos

```bash
# 1. Listar todos os apps do sistema
adb shell su -c 'lsp-available --category system'

# 2. Buscar apps relacionados a NFC
adb shell su -c 'lsp-available --search nfc --with-sizes'

# 3. Detalhes específicos de um app
adb shell su -c 'lsp-available --details com.android.systemui'

# Output detalhado:
📦 Package: com.android.systemui
🏷️  Categoria: system
📊 Versão: 14.0.0
⚡ Status: enabled
📁 APK: /system/app/SystemUI/SystemUI.apk
💾 Tamanho: 12.34 MB

🔐 Permissões principais:
    - android.permission.SYSTEM_ALERT_WINDOW
    - android.permission.STATUS_BAR_SERVICE
    - android.permission.MANAGE_USERS

🎯 Uso como escopo:
    - Módulo: de.tu_darmstadt.seemoo.nfcgate (user 0)
    - Módulo: com.ceco.pie.gravitybox (user 0)

💡 Módulos que podem usar este escopo:
    - de.tu_darmstadt.seemoo.nfcgate (default)
    - com.ceco.pie.gravitybox (default)
    - tk.wasdennnoch.androidn_ify (pattern: systemui)
```

### Caso 8: Descoberta por Categoria

```bash
# Apps do Google instalados
adb shell su -c 'lsp-available --category google --format json'

# Apps Samsung com tamanhos
adb shell su -c 'lsp-available --category samsung --enabled-only --with-sizes'

# Apps de câmera
adb shell su -c 'lsp-available --category camera'
```

---

## 🛠️ Manutenção e Troubleshooting

### Caso 9: Diagnóstico Completo

```bash
# 1. Health check completo
adb shell su -c 'lsp-health'

# 2. Verificar problemas específicos
adb shell su -c 'lsp-list --broken'  # Módulos com APK inexistente
adb shell su -c 'lsp-list --without-scopes --enabled'  # Módulos ativos sem escopos
adb shell su -c 'lsp-scopes --only-installed'  # Escopos de apps instalados
```

### Caso 10: Gerenciamento de Backups

```bash
# 1. Criar backup antes de mudanças importantes
adb shell su -c 'lsp-backup --create "antes_configuracao_nfc"'

# 2. Listar backups existentes
adb shell su -c 'lsp-backup --list'

# 3. Informações detalhadas de um backup
adb shell su -c 'lsp-backup --info 3'

# 4. Restaurar backup se algo der errado
adb shell su -c 'lsp-backup --restore 3'

# 5. Limpeza automática (manter últimos 10)
adb shell su -c 'lsp-backup --cleanup --keep 10'
```

### Caso 11: Limpeza Geral

```bash
# Limpeza completa do sistema
adb shell su -c 'lsp-bulk --cleanup --dry-run'

# Aplicar limpeza
adb shell su -c 'lsp-bulk --cleanup --force'

# Output:
1. Removendo escopos de apps não instalados...
2. Verificando escopos órfãos...
3. Verificando integridade do banco...
4. Otimizando banco de dados...
```

---

## 🤖 Automação e Scripts

### Caso 12: Script de Configuração Personalizada

```bash
#!/system/bin/sh
# config_nfc_research.sh - Setup para pesquisa NFC

# Carregar ambiente
source /data/local/tmp/lsposed-cli/aliases.sh

# Backup de segurança
lsp-backup --create "nfc_research_setup"

# Habilitar módulos necessários
echo "Configurando ambiente para pesquisa NFC..."

# NFCGate com escopos específicos
lsp-enable --auto de.tu_darmstadt.seemoo.nfcgate

# Verificar se foi aplicado corretamente
if lsp-list --module de.tu_darmstadt.seemoo.nfcgate | grep -q "✅ ON"; then
    echo "✅ NFCGate configurado com sucesso"
else
    echo "❌ Falha na configuração do NFCGate"
    exit 1
fi

echo "🔄 Reinicie o dispositivo para aplicar as mudanças"
```

### Caso 13: Monitoramento Automático

```bash
#!/system/bin/sh
# monitor_modules.sh - Monitoramento de módulos

# Função para verificar status
check_modules() {
    local issues=0
    
    # Verificar módulos órfãos
    local broken=$(lsp-list --broken | tail -n +4 | wc -l)
    if [ "$broken" -gt 0 ]; then
        echo "⚠️  $broken módulo(s) com problemas detectados"
        issues=$((issues + 1))
    fi
    
    # Verificar escopos inválidos
    local invalid_scopes=$(lsp-scopes --only-installed | wc -l)
    local total_scopes=$(lsp-scopes | wc -l)
    local missing=$((total_scopes - invalid_scopes))
    
    if [ "$missing" -gt 0 ]; then
        echo "⚠️  $missing escopo(s) de apps não instalados"
        issues=$((issues + 1))
    fi
    
    return $issues
}

# Executar verificação
if check_modules; then
    echo "✅ Todos os módulos estão em ordem"
else
    echo "🛠️  Problemas detectados - execute lsp-health para detalhes"
fi
```

### Caso 14: Backup Automático Agendado

```bash
#!/system/bin/sh
# daily_backup.sh - Backup automático diário

# Configurações
MAX_BACKUPS=7
TAG="daily_$(date +%u)"  # day of week

# Carregar ambiente
source /data/local/tmp/lsposed-cli/aliases.sh

# Verificar se houve mudanças desde o último backup
LAST_BACKUP=$(lsp-backup --list | tail -1 | awk '{print $2}')
DB_MODIFIED=$(stat -c %Y /data/adb/lspd/config/modules_config.db)
LAST_BACKUP_TIME=$(echo "$LAST_BACKUP" | sed 's/.*_\([0-9]*\).*/\1/')

if [ "$DB_MODIFIED" -gt "$LAST_BACKUP_TIME" ]; then
    echo "📅 Criando backup diário..."
    lsp-backup --create "$TAG"
    
    # Limpeza automática
    lsp-backup --cleanup --keep "$MAX_BACKUPS"
    
    echo "✅ Backup diário concluído"
else
    echo "ℹ️  Nenhuma mudança desde o último backup"
fi
```

---

## 📋 Casos de Uso Específicos

### Caso 15: Configuração para Desenvolvimento

```bash
# Setup completo para desenvolvimento de módulos
cat > /sdcard/dev_setup.txt <<EOF
# Framework essencial
io.github.lsposed.manager
com.github.kyuubiran.ezxhelper

# Módulos de teste
de.robv.android.xposed.mods.tutorial
tk.wasdennnoch.androidn_ify
EOF

# Aplicar configuração
adb shell su -c 'lsp-bulk --enable --scope-mode auto --file /sdcard/dev_setup.txt'

# Verificar resultado
adb shell su -c 'lsp-status'
```

### Caso 16: Migração entre Dispositivos

```bash
# No dispositivo origem
adb shell su -c 'lsp-backup --create "migration_$(date +%Y%m%d)"'
adb pull /data/local/tmp/lsposed-cli/backups/backup_*.tar.gz ./

# No dispositivo destino
adb push backup_*.tar.gz /sdcard/
adb shell su -c 'lsp-backup --restore /sdcard/backup_*.tar.gz'
```

### Caso 17: Reset Completo

```bash
# Reset total com backup
adb shell su -c 'lsp-backup --create "before_reset"'
adb shell su -c 'lsp-bulk --disable --force $(lsp-list --enabled --format minimal)'
adb shell su -c 'lsp-bulk --reset-scopes --force $(lsp-list --format minimal)'
adb shell su -c 'lsp-health'
```

---

## 🎯 Dicas e Melhores Práticas

### Workflow Recomendado

1. **Sempre fazer backup antes de mudanças importantes**
2. **Usar --dry-run para preview de operações complexas**
3. **Verificar compatibilidade com lsp-available --details**
4. **Monitorar saúde do sistema com lsp-health**
5. **Manter backups organizados por tags**

### Shortcuts Úteis

```bash
# Aliases personalizados adicionais
alias lsp-status='lsp-list && echo && lsp-scopes'
alias lsp-find='lsp-available --search'
alias lsp-safe-enable='lsp-backup --create "auto_$(date +%H%M)" && lsp-enable'
```

### Troubleshooting Rápido

```bash
# Problemas comuns e soluções
lsp-health                           # Diagnóstico geral
lsp-list --broken                    # Módulos com problemas
lsp-scopes --only-installed          # Escopos válidos
lsp-backup --list                    # Backups disponíveis
lsp-bulk --cleanup --dry-run         # Preview de limpeza
```

---

Este guia cobre os principais cenários de uso do LSPosed CLI Tools. Para mais informações, consulte a documentação individual de cada script com `<comando> --help`.
