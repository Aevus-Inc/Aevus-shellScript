#!/bin/bash

# Atualizar o sistema e instalar pacotes necessários
echo "Atualizando o sistema e instalando pacotes essenciais..."
sudo apt update -y && sudo apt upgrade -y
sudo apt install -y docker.io docker-compose npm openjdk-21-jdk git curl || {
  echo "Erro na instalação de pacotes. Verifique a conexão com a internet e tente novamente."
  exit 1
}

# Habilitar e iniciar o serviço Docker
echo "Habilitando e iniciando o serviço Docker..."
sudo systemctl enable docker
sudo systemctl start docker

# Preparar diretório do projeto
echo "Preparando o diretório do projeto..."
sudo mkdir -p /etc/projeto
cd /etc/projeto || exit 1

# Clonar os repositórios necessários
echo "Clonando repositórios..."
git clone https://github.com/Aevus-Inc/Projeto-Aevus.git || { echo "Erro ao clonar Projeto-Aevus"; exit 1; }
git clone https://github.com/Aevus-Inc/Java-Backend-Aevus.git || { echo "Erro ao clonar Java-Backend-Aevus"; exit 1; }
git clone https://github.com/Aevus-Inc/Aevus-DB.git || { echo "Erro ao clonar Aevus-DB"; exit 1; }

# Voltar ao diretório principal e mover o script SQL
echo "Movendo scripts SQL..."
mv Aevus-DB/script-aevus.sql . || { echo "Erro ao mover script-aevus.sql"; exit 1; }
mv Aevus-DB/create_user.sql . || { echo "Erro ao mover create_user.sql"; exit 1; }

# Download do script wait-for-it.sh para o container Java
echo "Baixando o script wait-for-it.sh..."
curl -o wait-for-it.sh https://raw.githubusercontent.com/vishnubob/wait-for-it/master/wait-for-it.sh || { echo "Erro ao baixar wait-for-it.sh"; exit 1; }
chmod +x wait-for-it.sh

# Criar Dockerfile para o serviço Java
echo "Criando Dockerfile para o serviço Java..."
cat <<EOL > Dockerfile-java
FROM openjdk:21-slim

WORKDIR /app

# Copia o diretório inteiro
COPY ./Java-Backend-Aevus /app/Java-Backend-Aevus
COPY ./wait-for-it.sh /usr/local/bin/wait-for-it.sh
RUN chmod +x /usr/local/bin/wait-for-it.sh

# Ajusta o comando para usar o arquivo dentro do diretório copiado
CMD ["bash", "-c", "/usr/local/bin/wait-for-it.sh mysql:3306 -- bash -c 'cd /app/Java-Backend-Aevus/target && java -Xms512m -Xmx4g -jar example-s3-bucket-v2-1.0-SNAPSHOT-jar-with-dependencies.jar'"]

EOL

# Criar Dockerfile para o serviço Node.js
echo "Criando Dockerfile para o serviço Node.js..."
cat <<EOL > Dockerfile-node
FROM node:16

WORKDIR /app

# Copia o diretório inteiro
COPY ./Java-Backend-Aevus /app/Java-Backend-Aevus
COPY ./wait-for-it.sh /usr/local/bin/wait-for-it.sh
RUN chmod +x /usr/local/bin/wait-for-it.sh

# Ajusta o comando para usar o arquivo dentro do diretório copiado
CMD ["bash", "-c", "/usr/local/bin/wait-for-it.sh mysql:3306 -- bash -c 'cd /app/Java-Backend-Aevus/target && java -Xms512m -Xmx4g -jar example-s3-bucket-v2-1.0-SNAPSHOT-jar-with-dependencies.jar'"]

EOL

# Criar Dockerfile para o serviço Node.js
echo "Criando Dockerfile para o serviço Node.js..."
cat <<EOL > Dockerfile-node
FROM node:16

WORKDIR /app
# Copiar os arquivos de dependências
COPY Projeto-Aevus/package*.json ./
# Instalar as dependências
RUN npm install

# Copiar o restante dos arquivos da aplicação
COPY Projeto-Aevus/ ./

# Expor a porta que a aplicação usará
EXPOSE 3333

# Comando para iniciar a aplicação
CMD ["npm", "run", "dev"]
EOL

# Criar o arquivo docker-compose.yml
echo "Criando o arquivo docker-compose.yml..."
cat <<EOL > docker-compose.yml
version: '3.8'
services:
  java:
    build:
      context: .
      dockerfile: Dockerfile-java
    container_name: ContainerJavaAevus
    depends_on:
      - mysql
    environment:
      - SLACK_WEBHOOK_URL=https://hooks.slack.com/services/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

  mysql:
    image: mysql:8
    container_name: ContainerBDAevus
    environment:
      MYSQL_ROOT_PASSWORD: urubu100
      MYSQL_DATABASE: banco1
    ports:
      - '3306:3306'
    volumes:
      - mysql-data:/var/lib/mysql
      - ./script-aevus.sql:/docker-entrypoint-initdb.d/script-aevus.sql
      - ./create_user.sql:/docker-entrypoint-initdb.d/create_user.sql
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost"]
      interval: 10s
      retries: 5

  node:
    build:
      context: .
      dockerfile: Dockerfile-node
    container_name: ContainerNodeSiteAevus
    ports:
      - '3333:3333'
    depends_on:
      - mysql

volumes:
  mysql-data:
EOL

# Iniciar os containers com Docker Compose
echo "Iniciando os containers com Docker Compose..."
sudo docker-compose up -d --build || { echo "Erro ao iniciar containers"; exit 1; }

# Configurar Crontab para reiniciar o container Java
echo "Configurando Crontab para garantir que o container Java esteja sempre rodando..."
(crontab -l 2>/dev/null; echo "5 * * * * docker start ContainerJavaAevus || true") | crontab -

echo "Setup completo! Serviços iniciados com sucesso."