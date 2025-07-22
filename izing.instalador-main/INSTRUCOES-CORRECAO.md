# Correção do Problema de Mensagens Duplicadas

## Problema Identificado
Quando você envia uma mensagem para um usuário no WhatsApp, na sua tela aparece a mensagem duplicada:
- Uma com relógio de "enviando" 
- Outra com 2 traços de "enviado"

Porém quem recebeu recebe somente 1 mensagem, que é o correto.

## Solução Implementada

### Para Novas Instalações
O instalador foi modificado para incluir automaticamente a correção do problema de mensagens duplicadas. As funções `backend_fix_duplicate_messages()` e `backend_fix_duplicate_messages_backend()` foram adicionadas ao processo de instalação.

### Para Instalações Existentes

#### Opção 1: Script Automático
Execute o script de correção:

```bash
cd /root/izinginstalador
sudo chmod +x fix-duplicate-messages.sh
sudo ./fix-duplicate-messages.sh
```

#### Opção 2: Correção Manual

1. **Corrigir Frontend:**
```bash
sudo su - deploy
cd /home/deploy/izing1/frontend/src

# Criar script de correção
cat > fix-duplicate-messages.js << 'EOF'
const fs = require('fs');
const path = require('path');

function fixDuplicateMessages(dir) {
  const files = fs.readdirSync(dir);
  
  files.forEach(file => {
    const filePath = path.join(dir, file);
    const stat = fs.statSync(filePath);
    
    if (stat.isDirectory()) {
      fixDuplicateMessages(filePath);
    } else if (file.endsWith('.vue') || file.endsWith('.js')) {
      let content = fs.readFileSync(filePath, 'utf8');
      
      if (content.includes('sendMessage') || content.includes('messages.push')) {
        // Substituir lógica de adição de mensagens
        content = content.replace(
          /this\.messages\.push\(([^)]+)\)/g,
          'const existingMsg = this.messages.find(msg => msg.key && msg.key.id === $1.key && $1.key.id); if (!existingMsg) { this.messages.push($1); }'
        );
        
        // Corrigir lógica de status de mensagem
        content = content.replace(
          /msg\.status\s*=\s*["']SENT["']/g,
          'const msgIndex = this.messages.findIndex(m => m.key && m.key.id === msg.key && msg.key.id); if (msgIndex !== -1) { this.messages[msgIndex].status = "SENT"; }'
        );
        
        // Adicionar verificação de duplicação antes de adicionar mensagens
        content = content.replace(
          /this\.messages\.unshift\(([^)]+)\)/g,
          'const existingMsg = this.messages.find(msg => msg.key && msg.key.id === $1.key && $1.key.id); if (!existingMsg) { this.messages.unshift($1); }'
        );
        
        fs.writeFileSync(filePath, content);
        console.log('Fixed:', filePath);
      }
    }
  });
}

fixDuplicateMessages('.');
EOF

# Executar correção
node fix-duplicate-messages.js

# Remover arquivo temporário
rm fix-duplicate-messages.js

# Recompilar o frontend
cd /home/deploy/izing1/frontend
export NODE_OPTIONS=--openssl-legacy-provider
npx quasar build -P -m pwa

# Reiniciar PM2
pm2 restart izing1-frontend
```

2. **Corrigir Backend:**
```bash
sudo su - deploy
cd /home/deploy/izing1/backend/src

# Criar script de correção
cat > fix-backend-duplicate-messages.js << 'EOF'
const fs = require('fs');
const path = require('path');

function fixBackendDuplicateMessages(dir) {
  const files = fs.readdirSync(dir);
  
  files.forEach(file => {
    const filePath = path.join(dir, file);
    const stat = fs.statSync(filePath);
    
    if (stat.isDirectory()) {
      fixBackendDuplicateMessages(filePath);
    } else if (file.endsWith('.js')) {
      let content = fs.readFileSync(filePath, 'utf8');
      
      if (content.includes('sendMessage') || content.includes('message') || content.includes('socket')) {
        // Adicionar verificação de duplicação antes de emitir eventos
        content = content.replace(
          /socket\.emit\(['"]message['"],\s*([^)]+)\)/g,
          'const messageId = $1.key && $1.key.id; if (messageId && !sentMessages.has(messageId)) { sentMessages.add(messageId); socket.emit("message", $1); }'
        );
        
        // Adicionar Set para controlar mensagens enviadas
        if (content.includes('const io =') && !content.includes('sentMessages')) {
          content = content.replace(
            /const io =/,
            'const sentMessages = new Set();\nconst io ='
          );
        }
        
        // Corrigir lógica de status de mensagem
        content = content.replace(
          /msg\.status\s*=\s*["']SENT["']/g,
          'if (msg.key && msg.key.id) { msg.status = "SENT"; }'
        );
        
        fs.writeFileSync(filePath, content);
        console.log('Fixed backend:', filePath);
      }
    }
  });
}

fixBackendDuplicateMessages('.');
EOF

# Executar correção
node fix-backend-duplicate-messages.js

# Remover arquivo temporário
rm fix-backend-duplicate-messages.js

# Recompilar o backend
cd /home/deploy/izing1/backend
npm run build

# Reiniciar PM2
pm2 restart izing1-backend
```

## O que foi corrigido:

1. **Frontend (Vue.js/Quasar):**
   - Adicionada verificação de duplicação antes de adicionar mensagens ao array
   - Corrigida lógica de atualização de status de mensagens
   - Implementado controle para evitar mensagens duplicadas na interface

2. **Backend (Node.js):**
   - Adicionado controle de mensagens enviadas usando Set
   - Corrigida lógica de emissão de eventos via Socket.IO
   - Implementada verificação de duplicação antes de emitir eventos

## Resultado Esperado:
- ✅ Mensagens não aparecem mais duplicadas na interface
- ✅ Status de mensagens é atualizado corretamente
- ✅ Apenas uma mensagem é exibida por envio
- ✅ Funcionalidade de envio mantida intacta

## Verificação:
Após aplicar a correção, teste enviando uma mensagem e verifique se:
1. Apenas uma mensagem aparece na interface
2. O status muda de "enviando" para "enviado" corretamente
3. O destinatário recebe apenas uma mensagem 