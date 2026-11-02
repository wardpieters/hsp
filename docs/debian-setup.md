---
title: Debian guest setup
description: Configure Debian guests to use the shared HTTP proxy for shell tools, APT, and Docker Engine.
---

# Debian guest setup

Use this guide after provisioning and starting a Debian VM or LXC in the home environment. Terraform configures the guest's network, DNS records, and firewall rules; configure these settings inside the guest separately.

The shared forward proxy is `http://http-proxy.{{HSP_DOMAIN}}:3128`. Before continuing, select the proxy guest with `http_proxy_name = "http-proxy"`, apply the infrastructure configuration, and install and configure Squid on that guest. The client needs working DNS and TCP 3128 access to the proxy, and Squid must permit its requests. See the [shared HTTP forward proxy reference](firewall-roles.md#shared-http-forward-proxy).

Run the commands below as root inside the Debian guest, or prefix privileged commands with `sudo`. Preserve unrelated settings when editing existing files. These are client settings for guests using the proxy; the proxy guest itself needs direct internet access as described in the firewall reference.

## Section index

1. [Configure in one command](#configure-in-one-command)
2. [Login environment](#login-environment)
3. [APT package downloads](#apt-package-downloads)
4. [Docker Engine proxy and log rotation](#docker-engine-proxy-and-log-rotation)
5. [Verify access](#verify-access)

## Configure in one command

On the Debian host you want to configure, run this single line in a **root shell** with Bash, `jq`, and Docker Engine 23.0 or later already installed. It sets all three files below, preserves unrelated environment and Docker settings, and replaces the dedicated APT proxy file. Docker configuration is merged and validated in a temporary directory before the files are changed. The Docker restart can interrupt running containers.

```sh
bash -eu -c 'u="http://http-proxy.{{HSP_DOMAIN}}:3128"; t=$(mktemp -d); trap "rm -rf -- \"$t\"" EXIT; if [ -f /etc/docker/daemon.json ]; then cp /etc/docker/daemon.json "$t/input.json"; else printf "{}\n" > "$t/input.json"; fi; jq --arg u "$u" ".proxies += {\"http-proxy\": \$u, \"https-proxy\": \$u} | .[\"log-driver\"] = \"json-file\" | .[\"log-opts\"] += {\"max-size\": \"100m\", \"max-file\": \"3\"}" "$t/input.json" > "$t/daemon.json"; dockerd --validate --config-file="$t/daemon.json"; if [ -f /etc/environment ]; then sed -E "/^[[:space:]]*(export[[:space:]]+)?(http_proxy|HTTP_PROXY|https_proxy|HTTPS_PROXY)[[:space:]]*=/d" /etc/environment; fi > "$t/environment"; for k in http_proxy HTTP_PROXY https_proxy HTTPS_PROXY; do printf "%s=\"%s\"\n" "$k" "$u"; done >> "$t/environment"; mkdir -p /etc/apt/apt.conf.d /etc/docker; cat "$t/environment" > /etc/environment; printf "Acquire::http::Proxy \"%s\";\nAcquire::https::Proxy \"%s\";\n" "$u" "$u" > /etc/apt/apt.conf.d/99HttpProxy; cat "$t/daemon.json" > /etc/docker/daemon.json; systemctl restart docker'
```

Log out and back in to load the login environment, or run the shell exports below for immediate use. Continue with [Verify access](#verify-access), or use the individual steps below for hosts without Docker.

## Login environment

Edit the login environment:

```sh
nano /etc/environment
```

Add or update these entries:

```ini
http_proxy="http://http-proxy.{{HSP_DOMAIN}}:3128"
HTTP_PROXY="http://http-proxy.{{HSP_DOMAIN}}:3128"
https_proxy="http://http-proxy.{{HSP_DOMAIN}}:3128"
HTTPS_PROXY="http://http-proxy.{{HSP_DOMAIN}}:3128"
```

`/etc/environment` uses literal `KEY=value` entries, rather than shell commands. Do not put `export` or references such as `${http_proxy}` in this file. Debian login sessions that load it through PAM receive the values after logging out and back in. See the [PAM environment documentation](https://manpages.debian.org/trixie/libpam-runtime/pam_env.8.en.html).

To apply the same settings immediately to the current shell, run:

```sh
export http_proxy="http://http-proxy.{{HSP_DOMAIN}}:3128"
export HTTP_PROXY="${http_proxy}"
export https_proxy="http://http-proxy.{{HSP_DOMAIN}}:3128"
export HTTPS_PROXY="${https_proxy}"
```

Both URLs use `http://` because the connection to Squid is HTTP; HTTPS destinations are reached through an HTTP CONNECT tunnel. Applications must support these variables to use them. System services and application containers need their own proxy configuration.

## APT package downloads

Configure APT explicitly so package downloads also work outside an interactive login shell:

```sh
nano /etc/apt/apt.conf.d/99HttpProxy
```

Add:

```text
Acquire::http::Proxy "http://http-proxy.{{HSP_DOMAIN}}:3128";
Acquire::https::Proxy "http://http-proxy.{{HSP_DOMAIN}}:3128";
```

APT reads this file on its next invocation; no service restart is needed. The HTTPS entry makes the setting explicit for HTTPS repositories as well. See Debian's [HTTP transport](https://manpages.debian.org/bookworm/apt/apt-transport-http.1.en.html) and [HTTPS transport](https://manpages.debian.org/bookworm/apt/apt-transport-https.1.en.html) references.

## Docker Engine proxy and log rotation

On guests running Docker, configure the system Docker Engine daemon separately from the login environment. The `proxies` settings below require Docker Engine 23.0 or later; check with `dockerd --version`. See the [Docker daemon reference](https://docs.docker.com/reference/cli/dockerd/#proxy-configuration).

```sh
mkdir -p /etc/docker
nano /etc/docker/daemon.json
```

Use this configuration, merging the keys into the existing JSON object if the file already contains settings:

```json
{
  "proxies": {
    "http-proxy": "http://http-proxy.{{HSP_DOMAIN}}:3128",
    "https-proxy": "http://http-proxy.{{HSP_DOMAIN}}:3128"
  },
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
```

Validate the file before restarting Docker:

```sh
dockerd --validate --config-file=/etc/docker/daemon.json
```

If validation succeeds, restart Docker and check the service:

```sh
systemctl restart docker
systemctl is-active docker
```

Restarting Docker can interrupt running containers. The daemon proxy enables registry operations such as image pulls; configure proxy settings separately for applications inside containers and for build steps that need web access. See [Docker daemon proxy configuration](https://docs.docker.com/engine/daemon/proxy/).

The logging defaults rotate each container's JSON logs at `100m`, retaining up to three files. They apply to newly created containers; recreate existing containers to adopt them unless the workload specifies its own logging options. Keep the option values quoted as strings. See [Docker's JSON file logging driver](https://docs.docker.com/engine/logging/drivers/json-file/).

## Verify access

Check DNS and package downloads:

```sh
getent hosts "http-proxy.{{HSP_DOMAIN}}"
apt-config dump | grep -i proxy
apt-get update
```

If `curl` is installed, test HTTPS using the current shell's proxy environment:

```sh
curl --fail --head --connect-timeout 10 https://deb.debian.org/debian/
```

On a Docker guest, verify that the daemon can pull an image:

```sh
docker pull hello-world:latest
```

If requests time out, check DNS, guest access to TCP 3128, the Squid listener and ACLs, and the proxy guest's outbound TCP 80/443 rules. A Squid `403` response usually points to an ACL denial. For Docker startup errors, inspect `journalctl -u docker -n 50 --no-pager`. Direct internet access can remain blocked by the guest firewall even when these proxied requests succeed.
