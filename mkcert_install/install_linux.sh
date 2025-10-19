#!/bin/bash

# Script de instalación para Linux: Instala Go, certutil y compila mkcert.

REPO="FiloSottile/mkcert"

# Asegurar que se tienen permisos de sudo al inicio para evitar múltiples prompts de contraseña.
if ! sudo -v; then
    echo "Error: Se requiere permiso de sudo. Abortando instalación de Linux."
    exit 1
fi

echo "Iniciando instalación de dependencias en Linux..."

# 1. Verificar e instalar Go (Si no está presente)
if ! command -v go &> /dev/null; then
    echo "🚨 Go no está instalado. Instalando Go (golang)..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y golang
    elif command -v yum &> /dev/null; then
        sudo yum install -y golang
    elif command -v pacman &> /dev/null; then
        sudo pacman -Syu --noconfirm go
    elif command -v zypper &> /dev/null; then
        sudo zypper install -y go
    else
        echo "Error: No se encontró un gestor de paquetes conocido para instalar Go."
        exit 1
    fi
    echo "✅ Go instalado."
fi

# 2. Instalar certutil
echo "Instalando la utilidad 'certutil' (libnss3-tools/nss-tools)..."
if command -v apt-get &> /dev/null; then
    sudo apt-get install -y libnss3-tools
elif command -v yum &> /dev/null; then
    sudo yum install -y nss-tools
elif command -v pacman &> /dev/null; then
    sudo pacman -S --noconfirm nss
elif command -v zypper &> /dev/null; then
    sudo zypper install -y mozilla-nss-tools
else
    echo "Advertencia: No se pudo instalar certutil automáticamente. Puede fallar la confianza del CA."
fi

# 3. Compilación e Instalación de mkcert
echo "Descargando, compilando e instalando mkcert..."

if ! command -v git &> /dev/null; then
    echo "Error: Git no está instalado, es necesario para clonar el repositorio."
    exit 1
fi

TEMP_DIR=$(mktemp -d)
cd "$TEMP_DIR" || exit 1

git clone "https://github.com/$REPO.git"
cd mkcert || exit 1

BUILD_VERSION=$(git describe --tags 2>/dev/null || echo "v1.0.0-custom")
go build -ldflags "-X main.Version=$BUILD_VERSION"

echo "Moviendo el binario a /usr/local/bin/ (requiere sudo)..."
sudo mv mkcert /usr/local/bin/

# Limpieza
cd ~
rm -rf "$TEMP_DIR"

echo "✅ mkcert compilado e instalado con éxito en Linux."
exit 0