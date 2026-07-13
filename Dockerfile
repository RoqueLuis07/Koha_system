# Koha on Railway
#
# Runs Koha directly from its git source tree (the same "dev install" mode
# used by koha-testing-docker), using Elasticsearch as the search engine so
# Zebra never needs to run. One image is shared by the staff (intranet) and
# OPAC services; which app is served is selected at runtime via SERVICE.

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8 \
    PERL5LIB=/app:/app/lib \
    PERL_MM_USE_DEFAULT=1 \
    KOHA_HOME=/app \
    KOHA_CONF=/etc/koha/koha-conf.xml \
    KOHA_INTRANET_PORT=8080 \
    KOHA_OPAC_PORT=8080

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        curl \
        ca-certificates \
        gnupg \
        git \
        cpanminus \
        perl \
        perl-doc \
        default-libmysqlclient-dev \
        default-mysql-client \
        libxml2-dev \
        libxslt1-dev \
        libssl-dev \
        zlib1g-dev \
        libgd-dev \
        libyaz-dev \
        yaz \
        libmagic-dev \
        uuid-dev \
        libfribidi-dev \
        libexpat1-dev \
        fontconfig \
        fonts-dejavu-core \
        gettext-base \
        poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Node.js + Yarn, needed to build the staff/OPAC front-end assets
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && corepack enable \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Perl dependencies first so this layer is cached across app changes
COPY cpanfile ./
RUN cpanm --notest Starman \
    && cpanm --notest --installdeps .

# Install JS dependencies
COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

# Now bring in the rest of the source tree and build front-end assets
COPY . .
RUN yarn build:prod

RUN mkdir -p \
        /var/log/koha/koha \
        /var/lib/koha/koha/uploads \
        /var/lib/koha/koha/tmp \
        /var/cache/koha/koha/templates \
        /var/lock/koha/koha/zebradb \
        /var/spool/koha/koha \
        /var/lib/koha/koha/plugins \
        /etc/koha/sms_send \
    && cp etc/log4perl.conf /etc/koha/log4perl.conf

COPY docker/koha-conf.xml.template /etc/koha/koha-conf.xml.template
COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
