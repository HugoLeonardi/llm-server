# LLM Server — Self-Hosted AI Stack

Stack Docker Compose pour un serveur IA self-hosted sur Ubuntu 24.04 avec GPU AMD via ROCm.

## Services

| Service | URL | Description |
|---------|-----|-------------|
| Authelia | `auth.alba-arietis.com` | SSO — portail d'authentification |
| Open WebUI | `chat.alba-arietis.com` | Interface chat LLM |
| Nextcloud | `cloud.alba-arietis.com` | Cloud privé |
| Portainer | `portainer.alba-arietis.com` | Gestion Docker |
| Ollama | `localhost:11434` | Runtime LLM (bare metal) |

## Matériel

| Composant | Spec |
|-----------|------|
| OS | Ubuntu 24.04 LTS |
| GPU | AMD RX 6950 XT — 16 Go VRAM |
| CPU | Intel Core i3-12100F |
| RAM | 32 Go DDR5 |
| Accélération | ROCm 6.4 |

## Architecture

```
Internet
    │ HTTPS :443
    ▼
  Caddy (Let's Encrypt)
    │ forward_auth
    ▼
  Authelia (SSO)
    │
    ├── Open WebUI ──► Ollama (bare metal, GPU)
    ├── Nextcloud ──► MariaDB + Redis
    └── Portainer
```

Ollama tourne **hors Docker** pour un accès direct au GPU sans overhead de virtualisation.
Les modèles sont stockés sur un disque NVMe dédié monté sur `/data`.

## Déploiement

### Prérequis

- Ubuntu 24.04 LTS
- Docker installé
- ROCm 6.4 installé
- Ports 80 et 443 redirigés depuis le routeur
- DNS : sous-domaines pointant vers l'IP publique du serveur

### Installation

```bash
git clone https://github.com/HugoLeonardi/llm-server.git
cd llm-server
bash setup.sh
```

Le script `setup.sh` gère dans l'ordre :

1. Mise à jour système + dépendances
2. Installation Docker
3. Installation ROCm
4. Configuration UFW (ports 22, 80, 443, 51820)
5. Génération du `.env` (secrets aléatoires + mot de passe Nextcloud)
6. Hash bcrypt du mot de passe Authelia
7. Installation et configuration Ollama
8. Démarrage de la stack Docker Compose

Chaque étape peut aussi être lancée individuellement :

```bash
bash setup.sh system    # mise à jour système
bash setup.sh docker    # installation Docker
bash setup.sh rocm      # installation ROCm
bash setup.sh ufw       # pare-feu
bash setup.sh env       # génération .env
bash setup.sh authelia-password  # hash mot de passe
bash setup.sh ollama    # installation Ollama
bash setup.sh stack     # démarrage stack
```

## Configuration

### Secrets (.env)

Le fichier `.env` est **exclu de Git**. Il est généré automatiquement par `setup.sh` avec `openssl rand`.
Variables requises :

```
AUTHELIA_JWT_SECRET
AUTHELIA_SESSION_SECRET
AUTHELIA_STORAGE_ENCRYPTION_KEY
WEBUI_SECRET_KEY
NEXTCLOUD_DB_PASSWORD
NEXTCLOUD_DB_ROOT_PASSWORD
NEXTCLOUD_ADMIN_USER
NEXTCLOUD_ADMIN_PASSWORD
```

### Ajouter un utilisateur Authelia

```bash
# Générer le hash du mot de passe
docker run --rm authelia/authelia:latest \
  authelia crypto hash generate bcrypt --password 'MotDePasse'

# Ajouter dans authelia/users_database.yml
# Authelia recharge le fichier automatiquement (pas de redémarrage requis)
```

### Ajouter un modèle Ollama

```bash
ollama pull qwen2.5:27b-instruct-q4_K_M
ollama pull qwen2.5:9b-instruct-q8_0
```

## Sécurité

- HTTPS automatique via Caddy + Let's Encrypt
- Tous les services protégés par Authelia (`forward_auth`)
- Secrets générés aléatoirement, jamais committés
- Ollama non exposé publiquement (accès Docker interne uniquement)
- Pare-feu UFW actif
- VPN WireGuard pour accès distant (Freebox)

## Commandes utiles

```bash
# État de la stack
sudo docker compose ps
sudo docker compose logs <service> --tail 50

# Redémarrer un service
sudo docker compose restart authelia

# État GPU
sudo journalctl -u ollama -n 10 --no-pager
nvtop

# Modèles disponibles
ollama list
```

## Prochaines étapes

- [ ] 2FA TOTP Authelia en production
- [ ] Hermes Agent (NousResearch)
- [ ] Monitoring (Grafana + Prometheus)
