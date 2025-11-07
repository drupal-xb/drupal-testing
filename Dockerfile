# Multi-stage build for Node.js
FROM node:24-slim AS node-stage

# Testing image used for GitLab CI
FROM php:8.3-apache AS base

# Copy Node.js binaries and modules from the official Node.js image
COPY --from=node-stage /usr/local/bin/node /usr/local/bin/
COPY --from=node-stage /usr/local/lib/node_modules /usr/local/lib/node_modules
# Create symlinks for npm and npx
RUN ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

# Install system packages and clean up in a single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsodium-dev \
    libpng-dev \
    libjpeg-dev \
    libfreetype6-dev \
    libicu-dev \
    libjpeg62-turbo-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    libzip-dev \
    libonig-dev \
    libxml2-dev \
    curl \
    jq \
    unzip \
    ca-certificates \
    sudo \
    git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
               /tmp/* \
               /var/tmp/* \
               /usr/share/doc/* \
               /usr/share/man/*

# Configure GD with jpeg and freetype support
RUN docker-php-ext-configure gd --with-freetype --with-jpeg

# Install PHP extensions required by Drupal
RUN docker-php-ext-install -j$(nproc) \
    sodium \
    pdo \
    pdo_mysql \
    mysqli \
    gd \
    opcache \
    zip \
    mbstring \
    xml \
    dom \
    simplexml


COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Configure Apache and PHP in a single layer
RUN a2enmod rewrite && \
    echo "memory_limit = -1" > /usr/local/etc/php/conf.d/cli-memory.ini && \
    echo "memory_limit = 512M" > /usr/local/etc/php/conf.d/apache-memory.ini

# Install Chrome and ChromeDriver for PHPUnit functional tests
RUN set -eux; \
    CHROME_VERSION=$(curl -s https://googlechromelabs.github.io/chrome-for-testing/last-known-good-versions-with-downloads.json | jq -r '.channels.Stable.version') && \
    curl -L "https://storage.googleapis.com/chrome-for-testing-public/${CHROME_VERSION}/linux64/chrome-linux64.zip" -o chrome-linux64.zip && \
    unzip chrome-linux64.zip -d /opt/ && \
    ln -sf /opt/chrome-linux64/chrome /usr/local/bin/google-chrome && \
    curl -L "https://storage.googleapis.com/chrome-for-testing-public/${CHROME_VERSION}/linux64/chromedriver-linux64.zip" -o chromedriver-linux64.zip && \
    unzip chromedriver-linux64.zip -d /usr/local/bin/ && \
    mv /usr/local/bin/chromedriver-linux64/chromedriver /usr/local/bin/ && \
    chmod +x /usr/local/bin/chromedriver && \
    # Clean up downloads in same layer
    rm -f chrome-linux64.zip chromedriver-linux64.zip && \
    rm -rf /usr/local/bin/chromedriver-linux64/

# Install Playwright with dependencies (cache-busted for latest browsers)
RUN set -eux; \
    date > /tmp/cache-bust && \
    npx playwright install --with-deps && \
    # Clean up in same layer to reduce size
    rm -f /tmp/cache-bust && \
    rm -rf /tmp/* \
           /var/tmp/* \
           /var/lib/apt/lists/* \
           ~/.npm \
           /usr/share/doc/* \
           /usr/share/man/*

WORKDIR /var/www/html
