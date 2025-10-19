#!/bin/bash

# Script de instalación para macOS: Usa Homebrew.

echo "Iniciando instalación de mkcert en macOS mediante Homebrew..."

# 1. Verificar Homebrew
if ! command -v brew &> /dev/null; then
    echo "Error: Homebrew no está instalado. Instálalo primero: /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
    exit 1
fi

# 2. Instalar mkcert
if brew install mkcert; then
    echo "✅ mkcert instalado con éxito."
    
    # 3. Instalar nss si se usa Firefox
    if command -v firefox &> /dev/null && ! brew list nss &> /dev/null; then
        echo "Instalando nss (para soporte de Firefox)..."
        brew install nss
    fi
    exit 0
else
    echo "Error al instalar mkcert con Homebrew."
    exit 1
fi