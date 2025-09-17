# Imagem base Python
FROM python:3.11-slim

# Variáveis para não travar o apt
ENV DEBIAN_FRONTEND=noninteractive

# Instala dependências do sistema
RUN apt-get update && apt-get install -y \
    samba-common-bin \
    iproute2 \
    net-tools \
    tcpdump \
    && rm -rf /var/lib/apt/lists/*

# Cria diretório da app
WORKDIR /app

# Copia requirements direto
COPY requirements.txt requirements.txt

# Instala dependências Python
RUN pip install --no-cache-dir -r requirements.txt

# Copia o código da aplicação
COPY app.py app.py

# Expõe porta Flask
EXPOSE 5000

# Comando de inicialização
CMD ["python", "app.py"]
