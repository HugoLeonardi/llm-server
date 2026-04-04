# CLAUDE.md — LLM Server

Projet de Hugo Leonardi : serveur LLM self-hosted pour usage professionnel
en ingénierie CVC (chauffage, ventilation, climatisation).

## Matériel

| Composant | Spec |
|-----------|------|
| OS | Ubuntu 24.04 LTS |
| GPU | AMD RX 6950 XT — 16 Go VRAM (ROCm 6.4) |
| CPU | Intel Core i5-12400 (à vérifier — README dit i3-12100F) |
| RAM | 32 Go DDR5 |

## Architecture cible (document de référence : architecture-serveur-llm.pdf)

- **Ollama** — bare metal, GPU via ROCm, port 11434
- **Open WebUI** — interface chat, connectée à Ollama + recherche web via SearXNG
- **SearXNG** — moteur de recherche meta (interne uniquement, pas exposé publiquement)
- **Nextcloud** — cloud privé (+ MariaDB + Redis)
- **Hermes Agent** — agent IA autonome (NousResearch)
- **Caddy** — reverse proxy HTTPS
- **Authelia** — SSO + 2FA
- **WireGuard** — VPN accès distant

## Dépôt GitHub

`https://github.com/HugoLeonardi/llm-server.git`

Le script `setup.sh` automatise l'intégralité du déploiement (système, Docker, ROCm, UFW, .env, Authelia, Ollama, stack). Chaque étape peut être lancée individuellement : `bash setup.sh [system|docker|rocm|ufw|env|authelia-password|ollama|stack]`

## État actuel

Stack déployée en production avec domaine réel. WireGuard n'est pas encore déployé.

Services actifs via Docker Compose :
- Caddy, Authelia, Open WebUI, SearXNG, Nextcloud (+ MariaDB + Redis), Portainer

Services bare metal :
- Ollama (systemd, port 11434, GPU AMD via ROCm 6.4)

## Réseau

- Domaine : `alba-arietis.com`
- HTTPS : Let's Encrypt automatique via Caddy (ACME HTTP-01)
- Ports exposés : 443 (HTTPS), 80 (requis pour le challenge ACME Let's Encrypt)
- UFW configuré : 22/tcp (SSH), 80/tcp, 443/tcp, 51820/udp (WireGuard)

| Service | URL |
|---------|-----|
| Authelia | https://auth.alba-arietis.com |
| Open WebUI | https://chat.alba-arietis.com |
| Nextcloud | https://cloud.alba-arietis.com |
| Portainer | https://portainer.alba-arietis.com |

## Compte Authelia

- Utilisateur : `hugo`
- Email : `hugoleonardi54@gmail.com`
- Groupe : `admins`
- Politique : `one_factor` (à passer en `two_factor` pour la production)

## Fichiers clés

```
llm-server/
├── docker-compose.yml       — orchestration des services
├── .env                     — secrets (ne jamais committer)
├── Caddyfile                — reverse proxy (Let's Encrypt, ACME HTTP-01)
├── authelia/
│   ├── configuration.yml    — config SSO
│   └── users_database.yml   — utilisateurs (hash bcrypt)
├── searxng/
│   └── settings.yml         — config SearXNG (JSON activé, limiter désactivé)
└── journal.txt              — historique des actions et décisions
```

## Décisions techniques importantes

- **Ollama bare metal** (pas dans Docker) : accès direct GPU sans overhead
- **Modèles Ollama stockés sur `/data/ollama/models`** : disque NVMe dédié (`OLLAMA_MODELS=/data/ollama/models`)
- **Caddy + Let's Encrypt** : certificat public automatique, reconnu par tous les navigateurs et appareils sans import manuel
- **Authelia `one_factor`** actuellement → `two_factor` (TOTP) à activer en production
- **Authelia recharge `users_database.yml` automatiquement** — pas besoin de restart pour ajouter un utilisateur
- **SQLite** pour le stockage Authelia → peut migrer vers Postgres en prod
- **`alba-arietis.com`** comme domaine réel (cookie valide, HTTPS valide)

## Problèmes connus et solutions

| Problème | Cause | Solution |
|----------|-------|----------|
| `permission denied` Docker socket | Session ouverte avant ajout au groupe | Fermer/rouvrir la session graphique |
| Fichiers authelia owned par root | Créés avec des droits root | `sudo chown -R hugo_leonardi:hugo_leonardi ~/llm-server/authelia/` |
| Authelia crash — domain invalide | `localhost` sans point interdit | Utiliser un vrai domaine |
| Authelia crash — scheme HTTP | Authelia 4.38+ exige HTTPS | Caddy + domaine réel + Let's Encrypt |

## Prochaines étapes

1. **Passer Authelia en `two_factor`** : activer TOTP pour la production
2. **Phase 3 — WireGuard** : VPN pour accès distant (Freebox)
4. **Phase 4 — Hermes Agent** : agent IA autonome (NousResearch)
5. **Phase 5 — Monitoring** : Grafana + Prometheus

## Commandes fréquentes

```bash
# Démarrer / arrêter
sudo docker compose up -d
sudo docker compose down

# État et logs
sudo docker compose ps
sudo docker compose logs <service> --tail 50

# Générer un hash bcrypt (nouveau mot de passe Authelia)
# Authelia recharge users_database.yml automatiquement — pas de restart
docker run --rm authelia/authelia:latest authelia crypto hash generate bcrypt --password 'MonMotDePasse'

# État GPU / Ollama
sudo journalctl -u ollama -n 10 --no-pager
ollama list

# Vérifier ROCm
rocminfo | grep gfx
```

## Modèles LLM recommandés (une fois Ollama installé)

| Modèle | Taille | Mode | Usage |
|--------|--------|------|-------|
| Qwen 2.5 14B Q4_K_M | ~9 Go | GPU-only | Polyvalent, CVC, français |
| Qwen3.5-27B Q3_K_M | ~14 Go | GPU-only | Meilleur raisonnement |
| Qwen 2.5 32B Q4_K_M | ~20 Go | GPU+CPU | Max qualité, offload RAM |
| Mistral Nemo 12B | ~7.5 Go | GPU-only | Léger, rapide |
