FROM rust:stretch

RUN echo "deb http://ftp.debian.org/debian stretch-backports main" >> /etc/apt/sources.list && \
    apt-get update && \
    apt-get dist-upgrade -y && \
    apt-get install  -y \
        build-essential \
        libboost-all-dev \
        runit \
        sqlite && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    touch /etc/inittab

# Install PowerDNS
RUN curl https://downloads.powerdns.com/releases/pdns-4.1.13.tar.bz2 | tar xvjf - && \
    cd pdns-4.1.13 && \
    ./configure --with-modules=remote && \
    make && \
    make install 

# Install PageKite
RUN curl -s https://pagekite.net/pk/ | bash

# Create a non privileged user to build the Rust code.
RUN useradd -m -d /home/user -p user user
RUN chown -R user /home/user

ARG server_url
ENV server_url ${server_url:-https://github.com/mozilla-iot/registration_server}
ARG server_branch
ENV server_branch ${server_branch:-master}

USER user
WORKDIR /home/user
RUN set -x && \
    git clone --depth 1 --recursive -b ${server_branch} ${server_url} && \
    cd registration_server && \
    cargo build --release --features mysql

USER root
ADD service /etc/service

ENTRYPOINT ["/usr/bin/runsvdir", "/etc/service"]

# We expect to find the configuration mounted in /home/user/config
# and to find the following files:
# - pdns.conf   : PowerDNS configuration.
# - config.toml : registration server configuration.
# - env         : used to source environment variables.
