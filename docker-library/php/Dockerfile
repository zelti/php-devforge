# One Dockerfile for every PHP version. The tag comes from docker-compose.yml
# (build.args), so adding a version means adding a service, not copying this file.
#
# Named PHP_TAG, not PHP_VERSION: the official php image already sets PHP_VERSION
# inside the container (to the full 8.4.24), and .env uses PHP_VERSION for the
# short default selector (84). Three different meanings, so this one gets its own name.
ARG PHP_TAG=8.4
FROM php:${PHP_TAG}-fpm
LABEL maintainer="Yostin Vargas"

ARG NVM_DIR=/usr/local/nvm
ARG NODE_VERSION=24
ARG PNPM_VERSION=latest
ARG PHP_XDEBUG=no

# Without this a failure on the left of a pipe is swallowed (hadolint DL4006).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive
ENV NVM_DIR=${NVM_DIR}
ENV NODE_VERSION=${NODE_VERSION}
ENV PHP_XDEBUG=${PHP_XDEBUG}

# Instalar dependencias del sistema and php
RUN apt-get update && apt-get install -y --no-install-recommends \
    libfreetype-dev \
    libjpeg62-turbo-dev \
    libpng-dev \
    libicu-dev \
    libzip-dev \
    libpq-dev \
    libxml2-dev \
    libxslt1-dev \
    libmagickwand-dev \
    libonig-dev \
    git sudo iproute2 openssh-client unzip rsync \
    xfonts-encodings xfonts-utils fontconfig libxrender1 \
    aspell aspell-en aspell-fr \
    build-essential unixodbc-dev \
    curl gnupg wget \
    vim nano less \
    cron apt-transport-https ca-certificates mailutils iputils-ping \
    && docker-php-ext-configure gd --with-freetype --with-jpeg \
    # opcache and mbstring are deliberately absent: the official php images already
    # ship both (opcache enabled in conf.d, mbstring compiled into the binary via
    # --enable-mbstring). Asking for them recompiled them for nothing, and from
    # PHP 8.5 opcache produces no shared module at all, which failed the build.
    && set -- gd intl zip pdo_mysql pdo_pgsql soap xsl bcmath exif pcntl \
    && docker-php-ext-install -j"$(nproc)" "$@" \
    && rm -rf /var/lib/apt/lists/*

# Extensiones PECL
RUN pecl install imagick redis apcu xdebug \
    && docker-php-ext-enable imagick redis apcu

# Instalar Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Dev user with its own group. 1000/1000 is the usual first user on Linux, so
# most hosts need no adjustment; the entrypoint fixes it via PUID/PGID otherwise.
RUN groupadd -g 1000 php-devforge \
    && useradd -u 1000 -g php-devforge -c "php dev" -m -d /home/php-devforge -s /bin/bash php-devforge \
    && chmod 755 /home/php-devforge

RUN echo 'php-devforge ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/php-devforge \
    && chmod 440 /etc/sudoers.d/php-devforge

RUN echo 'php-devforge ALL=(ALL) NOPASSWD:SETENV: ALL' | EDITOR='tee -a' visudo && echo 'www-data ALL=(ALL) NOPASSWD:SETENV: ALL' | EDITOR='tee -a' visudo

# Instalar NVM
RUN git clone https://github.com/nvm-sh/nvm.git ${NVM_DIR} \
    && git -C ${NVM_DIR} checkout "$(git -C ${NVM_DIR} describe --abbrev=0 --tags --match "v[0-9]*" "$(git -C ${NVM_DIR} rev-list --tags --max-count=1)")" \
    && chown -R php-devforge:www-data ${NVM_DIR} \
    && echo "export NVM_DIR=${NVM_DIR}" >> /etc/profile.d/nvm.sh \
    && echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /etc/profile.d/nvm.sh \
    && chmod +x /etc/profile.d/nvm.sh

# Node via nvm, plus pnpm. npm ships with Node and cannot be removed;
# pnpm is installed alongside it and is the one to prefer.
RUN . /etc/profile.d/nvm.sh \
    && nvm install ${NODE_VERSION} \
    && nvm alias default ${NODE_VERSION} \
    && nvm use default \
    && npm install -g pnpm@${PNPM_VERSION} \
    && chown -R php-devforge:www-data ${NVM_DIR} 

# Configuración de vim y scripts
RUN echo "let skip_defaults_vim = 1" >> /etc/vim/vimrc 

# Configuración PHP personalizada
COPY config_files/zz-docker.conf "/usr/local/etc/php-fpm.d/zz-docker.conf"
COPY config_files/bashrc "/usr/local/php-devforge/bashrc"
COPY config_files/docker-php-entrypoint "/usr/local/bin/docker-php-entrypoint"
COPY config_files/xdebug "/usr/local/bin/xdebug"

RUN chmod +x /usr/local/bin/xdebug \ 
    && chmod +x /usr/local/bin/docker-php-entrypoint \
    && mkdir -p /usr/local/etc/php/mods-available

COPY config_files/docker-php-ext-xdebug.ini "/usr/local/etc/php/mods-available/docker-php-ext-xdebug.ini"

WORKDIR /home/php-devforge
