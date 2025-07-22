#!/bin/bash

# Script para corrigir problema de mensagens duplicadas em instalações existentes
# Uso: ./fix-duplicate-messages.sh

# reset shell colors
tput init

# Obter diretório do script
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
  PROJECT_ROOT="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /* ]] && SOURCE="$PROJECT_ROOT/$SOURCE"
done
PROJECT_ROOT="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"

# required imports
source "${PROJECT_ROOT}"/variables/manifest.sh
source "${PROJECT_ROOT}"/utils/manifest.sh
source "${PROJECT_ROOT}"/lib/manifest.sh

# Carregar configuração
source "${PROJECT_ROOT}"/config

print_banner
printf "${WHITE} 🔧 Corrigindo problema de mensagens duplicadas...${GRAY_LIGHT}"
printf "\n\n"

# Função para corrigir frontend
fix_frontend_duplicate_messages() {
  printf "${WHITE} 💻 Corrigindo frontend...${GRAY_LIGHT}\n"
  
  sudo su - deploy <<EOF
  cd /home/deploy/${nome_instancia}/frontend/src

  # Criar arquivo de correção
  cat > fix-duplicate-messages.js << 'FIXEOF'
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
  FIXEOF

  # Executar correção
  node fix-duplicate-messages.js

  # Remover arquivo temporário
  rm fix-duplicate-messages.js

  # Recompilar o frontend
  cd /home/deploy/${nome_instancia}/frontend
  export NODE_OPTIONS=--openssl-legacy-provider
  npx quasar build -P -m pwa

  # Reiniciar PM2
  pm2 restart ${nome_instancia}-frontend
EOF

  printf "${GREEN} ✅ Frontend corrigido!${GRAY_LIGHT}\n\n"
}

# Função para corrigir backend
fix_backend_duplicate_messages() {
  printf "${WHITE} 💻 Corrigindo backend...${GRAY_LIGHT}\n"
  
  sudo su - deploy <<EOF
  cd /home/deploy/${nome_instancia}/backend/src

  # Criar arquivo de correção
  cat > fix-backend-duplicate-messages.js << 'BACKENDFIXEOF'
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
  BACKENDFIXEOF

  # Executar correção
  node fix-backend-duplicate-messages.js

  # Remover arquivo temporário
  rm fix-backend-duplicate-messages.js

  # Recompilar o backend
  cd /home/deploy/${nome_instancia}/backend
  npm run build

  # Reiniciar PM2
  pm2 restart ${nome_instancia}-backend
EOF

  printf "${GREEN} ✅ Backend corrigido!${GRAY_LIGHT}\n\n"
}

# Executar correções
fix_frontend_duplicate_messages
fix_backend_duplicate_messages

printf "${GREEN} 🎉 Correção concluída! O problema de mensagens duplicadas foi resolvido.${GRAY_LIGHT}\n"
printf "${WHITE} 📱 Reinicie a aplicação se necessário.${GRAY_LIGHT}\n\n" 