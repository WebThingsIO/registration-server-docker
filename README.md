# Docker Image for mozilla-iot/registration_server

This Docker image provides an easily deployable [registration server](https://github.com/mozilla-iot/registration_server) for the WebThings Gateway.

The setup relies on 3 components:
- The registration server
- A [PowerDNS](https://powerdns.com/) server
- [PageKite](https://pagekite.net/)

Getting a full setup ready involves the following:
- Build a Docker image.
- Install nginx on the container's host.
- Configure your DNS zone for the domain you want to use. The NS records need to point to your registration server. This will need to be done through your DNS host or domain registrar.

    ```
    $ dig +short NS mozilla-iot.org
    ns2.mozilla-iot.org.
    ns1.mozilla-iot.org.
    ```

- Run the Docker image with the proper configuration.

## Docker build

First, build the Docker image with `docker build -t registration-server .` from the source directory.

You can add the following build args:
* `--build-arg "server_url=https://github.com/<your-fork>/registration_server"`
* `--build-arg "server_branch=<your-branch>"`
* `--build-arg "db_type=<db-type>"`
    * `<db-type>` should be one of: mysql, sqlite, postgres

## Configuration files

* Add the following server directives to your `nginx.conf` on the host:

```
# HTTP version of the main registration server. We redirect to TLS port 8443 to
# avoid conflicting with tunneled domains.
server {
    listen 80;
    listen [::]:80;
    server_name api.mydomain.org;
    return 301 https://$server_name:8443$request_uri;
}

# This default server handles tunneled domains, i.e. myhost.mydomain.org.
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    return 301 https://$host$request_uri;
}

# This is the main registration server.
#
# This section assumes you're using Let's Encrypt to generate a host
# certificate. Adjust accordingly if necessary.
server {
    listen 8443 ssl http2 default_server;
    listen [::]:8443 ssl http2 default_server;
    server_name api.mydomain.org;

    ssl_certificate "/etc/letsencrypt/live/api.mydomain.org/fullchain.pem";
    ssl_certificate_key "/etc/letsencrypt/live/api.mydomain.org/privkey.pem";
    # It is *strongly* recommended to generate unique DH parameters
    # Generate them with: openssl dhparam -out /etc/pki/nginx/dhparams.pem 2048
    ssl_dhparam "/etc/pki/nginx/dhparams.pem";
    ssl_session_cache shared:SSL:1m;
    ssl_session_timeout  10m;
    ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
    ssl_ciphers HIGH:SEED:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!RSAPSK:!aDH:!aECDH:!EDH-DSS-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA:!SRP;
    ssl_prefer_server_ciphers on;

    location / {
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_pass http://127.0.0.1:81;
    }
}
```

* The `$CONFIG_DIR/pagekite.conf` file is used to set any options for PageKite. Here's a full example:
```
--isfrontend
--ports=4443
--protos=https
--authdomain=mydomain.org
--nullui
```

* The `$CONFIG_DIR/pdns.conf` is the PowerDNS configuration file. It needs to be consistent with the registration configuration to connect on the correct socket for the remote queries:
```
daemon=no
local-port=53
local-address=0.0.0.0
socket-dir=/run/
launch=remote
remote-connection-string=unix:path=/tmp/pdns_tunnel.sock
write-pid=no
log-dns-details=no
log-dns-queries=no
loglevel=4

# If using geoip in the registration server, uncomment the following:
#query-cache-ttl=0
#cache-ttl=0
```

* The `$CONFIG_DIR/config.toml` file holds the registration server configuration. Here's a sample consistent with the `pdns.conf` shown above:
```
# Configuration used for tests.

[general]
host = "0.0.0.0"
http_port = 81
domain = "mydomain.org"
db_path = "/home/user/data/domains.sqlite"

[pdns]
api_ttl = 1
dns_ttl = 86400
tunnel_ttl = 60
socket_path = "/tmp/pdns_tunnel.sock"
caa_record = "0 issue \"letsencrypt.org\""
mx_record = ""
ns_records = [
  [ "ns1.mydomain.org.", "5.6.7.8" ],
  [ "ns2.mydomain.org.", "4.5.6.7" ],
]
# Uncomment to set a PSL authentication record
# psl_record = "https://github.com/publicsuffix/list/pull/XYZ"
# Check your DNS configuration to fill in this field.
soa_record = "ns1.mydomain.org. dns-admin.mydomain.org. 2018082801 900 900 1209600 60"
txt_record = ""

  [pdns.geoip]
  default = "5.6.7.8"
  database = "/var/lib/GeoIP/GeoLite2-Country.mmdb"

    [pdns.geoip.continent]
    AF = "1.2.3.4"
    AN = "2.3.4.5"
    AS = "3.4.5.6"
    EU = "4.5.6.7"
    NA = "5.6.7.8"
    OC = "6.7.8.9"
    SA = "9.8.7.6"

[email]
server = "mail.gandi.net"
user = "accounts@mydomain.org"
password = "******"
sender = "accounts@mydomain.org"
reclamation_title = "Reclaim your Mozilla WebThings Gateway Domain"
reclamation_body = """Hello,
<br>
<br>
Your reclamation token is: {token}
<br>
<br>
If you did not request to reclaim your gateway domain, you can ignore this email."""
confirmation_title = "Welcome to your Mozilla WebThings Gateway"
confirmation_body = """Hello,
<br>
<br>
Welcome to your Mozilla WebThings Gateway! To confirm your email address, navigate to <a href="{link}">{link}</a>.
<br>
<br>
Your gateway can be accessed at <a href="https://{domain}">https://{domain}</a>."""
success_page = """<!DOCTYPE html>
<html>
  <head><title>Email Confirmation Successful!</title></head>
  <body>
    <h1>Thank you for verifying your email.</h1>
  </body>
</html>"""
error_page = """<!DOCTYPE html>
<html>
  <head><title>Email Confirmation Error!</title></head>
  <body>
    <h1>An error happened while verifying your email.</h1>
  </body>
</html>"""

```

* The `$CONFIG_DIR/GeoIP.conf` file holds the configuration for geoipupdate. This is only necessary if you're using geoip in the registration server.
```
# GeoIP.conf file for `geoipupdate` program, for versions >= 3.1.1.
# Used to update GeoIP databases from https://www.maxmind.com.
# For more information about this config file, visit the docs at
# https://dev.maxmind.com/geoip/geoipupdate/.

# `AccountID` is from your MaxMind account.
AccountID <your id>

# `LicenseKey` is from your MaxMind account
LicenseKey <your key>

# `EditionIDs` is from your MaxMind account.
EditionIDs GeoLite2-Country
```

By default the PageKite tunnel listens on port 4443.

Once you have all your configuration files ready, you can start the container as instructed below.

## Running the Docker image

You will have to mount a couple of directories and relay some ports for the Docker image to run properly:
- Mount `/home/user/config` to a directory where you will store the configuration files.
- Mount `/home/user/data` to a directory where the database will be stored (if using SQLite).

Port 53 over TCP and UDP needs to be forwarded for PowerDNS. The ports used for the HTTP server and the tunnel also need to be forwarded.

Example:

```bash
docker run \
    -d \
    -v /opt/docker/registration-server/config:/home/user/config \
    -v /opt/docker/registration-server/data:/home/user/data \
    -p 127.0.0.1:81:81 \
    -p 443:4443 \
    -p 53:53 \
    -p 53:53/udp \
    --restart unless-stopped \
    --name registration-server \
    registration-server
```
