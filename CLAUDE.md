# CLAUDE.md — LLM Server

Projet de Hugo Leonardi : serveur LLM self-hosted pour usage professionnel
en ingénierie CVC (chauffage, ventilation, climatisation).

## Matériel

| Composant | Spec |
|-----------|------|
| OS | Ubuntu 24.04 LTS |
| GPU | AMD RX 6950 XT — 16 Go VRAM (ROCm 7.x) |
| CPU | Intel Core i3 - 12100F |
| RAM | 32 Go DDR5 |

## Architecture cible (document de référence : architecture-serveur-llm.pdf)

- **Ollama** — bare metal, GPU via ROCm, port 11434
- **Open WebUI** — interface chat, connectée à Ollama
- **Nextcloud** — cloud privé (+ MariaDB + Redis)
- **Hermes Agent** — agent IA autonome (NousResearch)
- **Caddy** — reverse proxy HTTPS
- **Authelia** — SSO + 2FA
- **WireGuard** — VPN accès distant

## État actuel

Phase de test locale. Ollama et WireGuard ne sont pas encore déployés.

Services actifs via Docker Compose :
- Caddy, Authelia, Open WebUI, Nextcloud (+ MariaDB + Redis), Portainer

## Réseau local (tests)

- Domaine : `llm.test`
- HTTPS : certificat local Caddy (`tls internal`)
- Port : 443
- Entrées `/etc/hosts` : `127.0.0.1 auth.llm.test chat.llm.test cloud.llm.test portainer.llm.test`

| Service | URL |
|---------|-----|
| Authelia | https://auth.llm.test |
| Open WebUI | https://chat.llm.test |
| Nextcloud | https://cloud.llm.test |
| Portainer | https://portainer.llm.test |

## Compte Authelia

- Utilisateur : `hugo`
- Email : `hugoleonardi54@gmail.com`
- Groupe : `admins`
- Politique : `one_factor` (tests) → passer à `two_factor` en production

## Fichiers clés

```
llm-server/
├── docker-compose.yml       — orchestration des services
├── .env                     — secrets (ne jamais committer)
├── Caddyfile                — reverse proxy (tls internal pour tests)
├── authelia/
│   ├── configuration.yml    — config SSO
│   └── users_database.yml   — utilisateurs (hash bcrypt)
└── journal.txt              — historique des actions et décisions
```

## Décisions techniques importantes

- **Ollama bare metal** (pas dans Docker) : accès direct GPU sans overhead
- **Caddy `tls internal`** en local → Let's Encrypt automatique en production (juste changer le domaine)
- **Authelia `one_factor`** pour les tests → `two_factor` (TOTP) en production
- **SQLite** pour le stockage Authelia en test → peut migrer vers Postgres en prod
- **`llm.test`** comme domaine local car `localhost` n'est pas un domaine cookie valide pour Authelia

## Problèmes connus et solutions

| Problème | Cause | Solution |
|----------|-------|----------|
| `permission denied` Docker socket | Session ouverte avant ajout au groupe | Fermer/rouvrir la session graphique |
| Fichiers authelia owned par root | Créés avec des droits root | `sudo chown -R hugo_leonardi:hugo_leonardi ~/llm-server/authelia/` |
| Authelia crash — domain invalide | `localhost` sans point interdit | Utiliser `llm.test` |
| Authelia crash — scheme HTTP | Authelia 4.38+ exige HTTPS | Passer à `tls internal` + HTTPS |

## Prochaines étapes

1. **Valider la stack** : tester login Authelia, accès Open WebUI, Nextcloud, Portainer
2. **Confiance certificat** : importer `caddy-local-ca.crt` dans Firefox
3. **Phase 2 — Ollama** : installer ROCm + Ollama bare metal
4. **Phase 3 — WireGuard** : VPN pour accès distant
5. **Phase 4 — Hermes Agent** : agent IA autonome
6. **Production** : vrai domaine + Let's Encrypt + `two_factor` Authelia + `ufw`

## Commandes fréquentes

```bash
# Démarrer / arrêter
sudo docker compose up -d
sudo docker compose down

# État et logs
sudo docker compose ps
sudo docker compose logs <service> --tail 50

# Certificat CA local Caddy (pour Firefox)
sudo docker cp caddy:/data/caddy/pki/authorities/local/root.crt ~/llm-server/caddy-local-ca.crt

# Générer un hash bcrypt (nouveau mot de passe Authelia)
docker run --rm authelia/authelia:latest authelia crypto hash generate bcrypt --password 'MonMotDePasse'
```

## Modèles LLM recommandés (une fois Ollama installé)

| Modèle | Taille | Mode | Usage |
|--------|--------|------|-------|
| Qwen 2.5 14B Q4_K_M | ~9 Go | GPU-only | Polyvalent, CVC, français |
| Qwen3.5-27B Q3_K_M | ~14 Go | GPU-only | Meilleur raisonnement |
| Qwen 2.5 32B Q4_K_M | ~20 Go | GPU+CPU | Max qualité, offload RAM |
| Mistral Nemo 12B | ~7.5 Go | GPU-only | Léger, rapide |
