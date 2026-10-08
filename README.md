# Nilabiru Core

The core infrastructure stack for the Nilabiru ecosystem, bundling a Docker management dashboard, a reverse proxy with SSL certificate management, and an FRP client into a single Docker Compose setup with a simple deploy script.

---

## Overview

**Nilabiru Core** provisions three services in isolated Docker containers: Portainer for managing Docker, Nginx Proxy Manager for reverse proxying and SSL/TLS certificates, and an FRP client (`frpc`) that tunnels public traffic from a remote FRP server (such as `nilabiru-frps`) to Nginx Proxy Manager. Every admin interface is bound to the server's Tailscale IP, so only the ports needed for public traffic are exposed. Deployment is handled by a single `deploy.sh` script.

---

## Services

| Service                          | Image                             | Port(s)          | Description                                                                              |
| -------------------------------- | --------------------------------- | ---------------- | ---------------------------------------------------------------------------------------- |
| **nilabiru-portainer**           | `portainer/portainer-ce:2.42.0`   | `9443`, `8000`   | Web-based Docker management dashboard                                                    |
| **nilabiru-nginx-proxy-manager** | `jc21/nginx-proxy-manager:2.15.1` | `80`, `443`, `81` | Reverse proxy and SSL/TLS certificate management, with a web-based admin UI on port `81` |
| **nilabiru-frpc**                | `fatedier/frpc:v0.69.1`           | `7400`           | FRP client that tunnels traffic through an FRP server; web dashboard available at port `7400` |

All services run on the default Docker Compose network and use `restart: unless-stopped`. With the exception of Nginx Proxy Manager's HTTP/HTTPS ports (`80`, `443`), which are exposed on all network interfaces to allow public traffic and SSL certificate issuance, every other published port is bound to the Tailscale IP (`TAILSCALE_IP`) for secure private network access only — including the Portainer ports (`9443`, `8000`), the Nginx Proxy Manager admin UI (`81`), and the frpc web dashboard (`7400`).

`nilabiru-frpc` starts after `nilabiru-nginx-proxy-manager` (`depends_on`, condition `service_started`), and reaches it over the internal Docker network by its service name.

---

## Requirements

- Docker Engine `20.10+`
- Docker Compose `v2+`
- Tailscale installed and connected on the server and all client machines
- Ports `80` and `443` open/forwarded on the host (used by Nginx Proxy Manager for reverse proxying and SSL certificate issuance)
- A running FRP server reachable at `FRP_SERVER_ADDR` (e.g. [`nilabiru-frps`](https://github.com/NILABIRU/nilabiru-frps)), configured with the same token

---

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/NILABIRU/nilabiru-core.git
cd nilabiru-core
```

### 2. Configure environment variables

Copy the provided `env` file and fill in all values:

```bash
cp env .env
```

Then edit `.env`:

```env
# Tailscale
TAILSCALE_IP=

# FRP
FRP_SERVER_ADDR=
FRP_TOKEN=
FRP_USER=
FRP_PASSWORD=
```

> **Note:** Never commit `.env` to version control. It is already listed in `.gitignore`.

> **Note:** `FRP_TOKEN` must be identical to the token configured on the FRP server. `FRP_USER` and `FRP_PASSWORD` protect the frpc dashboard on port `7400`. Portainer and Nginx Proxy Manager need no environment variables — you create their admin accounts on first sign-in.

### 3. Prepare the frpc configuration

Ensure `frpc.toml` exists in the repository root and is configured to connect to your FRP server. The environment variables are passed into the container and should be referenced inside `frpc.toml` using FRP's environment variable expansion syntax:

```toml
serverAddr = "{{ .Envs.FRP_SERVER_ADDR }}"
serverPort = 7000

[auth]
method = "token"
token = "{{ .Envs.FRP_TOKEN }}"

[webServer]
addr = "0.0.0.0"
port = 7400
user = "{{ .Envs.FRP_USER }}"
password = "{{ .Envs.FRP_PASSWORD }}"

[[proxies]]
name = "http"
type = "tcp"
localIP = "nilabiru-nginx-proxy-manager"
localPort = 80
remotePort = 80

[[proxies]]
name = "https"
type = "tcp"
localIP = "nilabiru-nginx-proxy-manager"
localPort = 443
remotePort = 443
```

> **Note:** `localIP` uses the Docker service name `nilabiru-nginx-proxy-manager`, since frpc reaches Nginx Proxy Manager over the internal Docker network. `serverPort` must match the `bindPort` of the FRP server.

### 4. Start the stack

The recommended way is the provided deploy script:

```bash
chmod +x deploy.sh
./deploy.sh
```

`deploy.sh` stops on the first error (`set -e`) and does the following:

1. Validates the Compose configuration with `docker compose config --quiet`.
2. Deploys/redeploys all services with `docker compose up -d --remove-orphans --build`.
3. Always runs a cleanup on exit (even if a step fails) that removes dangling images with `docker image prune -f`.

Alternatively, you can start the stack directly:

```bash
docker compose up -d
```

To verify all services are running:

```bash
docker compose ps
```

---

## Service Access

Most services are accessible only via the Tailscale IP of the server. The exception is Nginx Proxy Manager's ports `80` and `443`, which are exposed publicly to handle reverse-proxied traffic and SSL certificate issuance for any domains configured behind it.

| Service                        | URL / Address                 |
| ------------------------------ | ----------------------------- |
| Portainer                      | `https://<TAILSCALE_IP>:9443` |
| Nginx Proxy Manager (Admin UI) | `http://<TAILSCALE_IP>:81`    |
| frpc Web Dashboard             | `http://<TAILSCALE_IP>:7400`  |

> **Note:** Portainer uses a self-signed certificate on port `9443`, so your browser will show a warning on first visit. Port `8000` is Portainer's Edge agent tunnel port; it is not used by regular agents (such as `nilabiru-portainer-agent`) and can be ignored unless you use Edge agents.

> **Note:** On first start, create your admin account promptly — Portainer shuts down its setup page if no admin is created within a few minutes (restart the container to reopen it). Nginx Proxy Manager's default login is `admin@example.com` / `changeme`; you are prompted to change it on first sign-in.

---

## Data Persistence

All stateful services use Docker named volumes for reliable persistence across restarts and redeployments.

| Volume / Mount                                  | Type         | Service                                   |
| ----------------------------------------------- | ------------ | ----------------------------------------- |
| `/var/run/docker.sock`                          | Bind mount   | Portainer (Docker socket access)          |
| `portainer-data`                                | Named volume | Portainer                                 |
| `npm-data`                                      | Named volume | Nginx Proxy Manager (config & database)   |
| `npm-letsencrypt`                               | Named volume | Nginx Proxy Manager (SSL certificates)    |
| `./frpc.toml`                                   | Bind mount (read-only) | frpc (configuration)            |

> **Note:** Mounting the Docker socket gives Portainer root-equivalent control over the host. Keep the Portainer ports restricted to the Tailscale network, as configured.

> **Note:** Back up `npm-data` and `npm-letsencrypt` regularly — they hold your proxy hosts, users, and SSL certificates.

---

## License

This project is licensed under the [MIT License](LICENSE).
Copyright © 2026 Andry Pebrianto