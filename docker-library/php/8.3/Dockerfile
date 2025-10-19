FROM php:8.3-fpm
LABEL maintainer="Yostin Vargas"

ARG PHP_VERSION=8.3
ARG NVM_DIR=/usr/local/nvm
ARG NODE_VERSION=19
ARG PHP_XDEBUG=no

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
    && docker-php-ext-install -j$(nproc) \
    gd \
    intl \
    zip \
    pdo_mysql \
    pdo_pgsql \
    soap \
    xsl \
    bcmath \
    opcache \
    mbstring \
    exif \
    pcntl \
    && rm -rf /var/lib/apt/lists/*

# Extensiones PECL
RUN pecl install imagick redis apcu xdebug \
    && docker-php-ext-enable imagick redis apcu

# Instalar Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Crear usuario php-devforge con UID/GID 33
RUN /usr/sbin/useradd -g 33 -o -u 33 -c "php dev" -m -d /home/php-devforge -s /bin/bash php-devforge \
    && sed -i -e "s/\\/var\\/www/\\/home\\/php-devforge/g" /etc/passwd

RUN echo 'php-devforge ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/php-devforge \
    && chmod 440 /etc/sudoers.d/php-devforge

RUN echo 'php-devforge ALL=(ALL) NOPASSWD:SETENV: ALL' | EDITOR='tee -a' visudo && echo 'www-data ALL=(ALL) NOPASSWD:SETENV: ALL' | EDITOR='tee -a' visudo

# Instalar NVM
RUN git clone https://github.com/nvm-sh/nvm.git ${NVM_DIR} \
    && cd ${NVM_DIR} \
    && git checkout "$(git describe --abbrev=0 --tags --match "v[0-9]*" "$(git rev-list --tags --max-count=1)")" \
    && chown -R php-devforge:www-data ${NVM_DIR} \
    && echo "export NVM_DIR=${NVM_DIR}" >> /etc/profile.d/nvm.sh \
    && echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> /etc/profile.d/nvm.sh \
    && chmod +x /etc/profile.d/nvm.sh

# Instalar Node 19 usando NVM
RUN . /etc/profile.d/nvm.sh \
    && nvm install ${NODE_VERSION} \
    && nvm alias default ${NODE_VERSION} \
    && nvm use default \
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

USER php-devforge
WORKDIR /home/php-devforge
