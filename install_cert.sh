#!/bin/bash

# --- CONFIGURACIÓN GLOBAL ---
REPO="FiloSottile/mkcert"
CERT_DIR="certificates"
CERT_NAME="php-devbox.pem"
KEY_NAME="php-devbox.key"
# ----------------------------

echo "Iniciando el gestor de instalación de mkcert..."

# 1. Leer la variable de entorno DEV_DOMAIN
if [ -f .env ]; then
    set -a
    . ./.env
    set +a
fi

if [ -z "$DEV_DOMAIN" ]; then
    echo "Error: No se pudo leer el dominio 'DEV_DOMAIN' del archivo .env. Abortando."
    exit 1
fi

echo "Dominio de desarrollo detectado: $DEV_DOMAIN"

# 2. Verificar si mkcert ya está instalado
INSTALLATION_SUCCESS=1
if command -v mkcert &> /dev/null; then
    echo "✅ mkcert ya está instalado. Versión: $(mkcert --version)"
    INSTALLATION_SUCCESS=0
else
    echo "❌ mkcert no encontrado. Iniciando instalación específica del SO..."
    
    OS=$(uname -s)
    if [[ "$OS" == "Linux" ]]; then
        if [ -f install_linux.sh ]; then
            bash mkcert_install/install_linux.sh
            INSTALLATION_SUCCESS=$? # Captura el código de salida del script secundario
        else
            echo "Error: Archivo mkcert_install/install_linux.sh no encontrado."
            exit 1
        fi
    elif [[ "$OS" == "Darwin" ]]; then
        if [ -f install_macos.sh ]; then
            bash mkcert_install/install_macos.sh
            INSTALLATION_SUCCESS=$?
        else
            echo "Error: Archivo mkcert_install/install_macos.sh no encontrado."
            exit 1
        fi
    elif [[ "$OS" == "MINGW"* ]] || [[ "$OS" == "CYGWIN"* ]]; then
        echo "Sistema detectado: Windows. Usa Chocolatey o Scoop para instalar mkcert."
        exit 0
    else
        echo "Sistema operativo ($OS) no reconocido."
        exit 1
    fi
fi

# 3. Pasos Post-instalación (Solo si mkcert está disponible o se instaló con éxito)
if [ "$INSTALLATION_SUCCESS" -eq 0 ] && command -v mkcert &> /dev/null; then
    echo "--------------------------------------------------"
    echo "Paso Post-Instalación: Configuración del Certificado."
    
    # 3.2. Generación del certificado Wildcard
    echo "--------------------------------------------------"
    echo "Generando certificado wildcard para *.$DEV_DOMAIN..."

    # *CORRECCIÓN*: Crear el directorio ANTES de llamar a mkcert
    mkdir -p "$CERT_DIR" 
    echo "Directorio de certificados creado en: ./$CERT_DIR"

    # Construir el comando mkcert
    mkcert_cmd="mkcert -cert-file \"${CERT_DIR}/${CERT_NAME}\" -key-file \"${CERT_DIR}/${KEY_NAME}\" \"$DEV_DOMAIN\" \"*.$DEV_DOMAIN\" 127.0.0.1 ::1 localhost"

    if eval "$mkcert_cmd"; then
        # 3.1. Instalación del CA local (Automático)
        echo "Ejecutando 'mkcert -install' para instalar la Autoridad Certificadora local..."
        if sudo mkcert -install; then
            echo "✅ Instalando certificados creados ✨"
        else
            echo "❌ Error al ejecutar 'mkcert -install'. Revise permisos."
            exit 1
        fi

        echo "✅ Certificados generados con éxito en la carpeta: **./$CERT_DIR**"
        echo "   - Certificado: **$CERT_DIR/$CERT_NAME**"
        echo "   - Clave: **$CERT_DIR/$KEY_NAME**"
        echo "¡Configuración completada! 🎉"
    else
        echo "❌ Error al generar los certificados."
        exit 1
    fi
else
    echo "La instalación de mkcert falló en el script secundario. Abortando pasos finales."
    exit 1
fi