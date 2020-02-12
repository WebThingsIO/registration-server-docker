FROM rust:buster

RUN echo "deb http://deb.debian.org/debian buster-backports main" >> /etc/apt/sources.list && \
    sed -i 's/ main$/ main contrib/g' /etc/apt/sources.list && \
    apt update && \
    apt dist-upgrade -y && \
    apt install  -y \
        cron \
        geoipupdate \
        pdns-backend-remote \
        pdns-server \
        runit && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    touch /etc/inittab

# Install PageKite
RUN curl -s https://pagekite.net/pk/ | bash

# Create a non privileged user to build the Rust code.
RUN useradd -m -d /home/user -p user user
RUN chown -R user /home/user

ARG server_url
ENV server_url ${server_url:-https://github.com/mozilla-iot/registration_server}
ARG server_branch
ENV server_branch ${server_branch:-master}
ARG db_type
ENV db_type ${db_type:-mysql}

USER user
WORKDIR /home/user
RUN set -x && \
    git clone --depth 1 --recursive -b "${server_branch}" "${server_url}" && \
    cd registration_server && \
    cargo build --release --features "${db_type}" && \
    cargo install diesel_cli

USER root
ADD init /
ADD etc/cron.weekly/geoipupdate /etc/cron.weekly/
ADD etc/service /etc/service

RUN sed -i "s/{{db_type}}/${db_type}/" /init

ENTRYPOINT ["/init"]

# We expect to find the configuration directory mounted at /home/user/config
# with the following files:
# - config.toml   : registration server configuration
# - pagekite.conf : PageKite configuration
# - pdns.conf     : PowerDNS configuration
