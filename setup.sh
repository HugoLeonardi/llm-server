#!/usr/bin/env bash
# =============================================================================
# setup.sh — Installation automatisée du serveur LLM
# Hugo Leonardi — Ubuntu 24.04 LTS — AMD RX 6950 XT (ROCm)
#
# Usage : bash setup.sh [étape]
#   bash setup.sh        → exécute toutes les étapes
#   bash setup.sh clone  → clone le dépôt GitHub
#   bash setup.sh system → mise à jour système
#   bash setup.sh docker → installation Docker
#   bash setup.sh rocm   → installation ROCm (GPU AMD)
#   bash setup.sh ufw    → configuration pare-feu
#   bash setup.sh disk   → formatage et montage du disque de données
#   bash setup.sh env    → génération du .env
#   bash setup.sh authelia-password → hash bcrypt mot de passe Authelia
#   bash setup.sh ollama → installation et configuration Ollama
#   bash setup.sh stack  → démarrage Docker Compose
# =============================================================================

set -euo pipefail

# ── Couleurs ─────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://github.com/HugoLeonardi/llm-server.git"
REPO_DIR="${HOME}/llm-server"
DOMAIN="alba-arietis.com"

# =============================================================================
# 0. CLONAGE DU DÉPÔT
# =============================================================================
step_clone() {
    if [[ -d "${REPO_DIR}/.git" ]]; then
        success "Dépôt déjà cloné dans ${REPO_DIR}."
        return
    fi

    info "Clonage du dépôt ${REPO_URL}..."
    git clone "$REPO_URL" "$REPO_DIR"
    success "Dépôt cloné dans ${REPO_DIR}."
}

# =============================================================================
# 1. MISE À JOUR SYSTÈME
# =============================================================================
step_system() {
    info "Mise à jour du système..."
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl git wget gnupg ca-certificates lsb-release openssl gdisk
    success "Système à jour."
}

# =============================================================================
# 2. DOCKER ENGINE + DOCKER COMPOSE
# =============================================================================
step_docker() {
    if command -v docker &>/dev/null; then
        success "Docker déjà installé : $(docker --version)"
        return
    fi

    info "Installation de Docker..."

    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    sudo usermod -aG docker "$USER"
    success "Docker installé. IMPORTANT : ferme et rouvre ta session pour que le groupe docker soit actif."
}

# =============================================================================
# 3. ROCm (GPU AMD RX 6950 XT — gfx1100)
# =============================================================================
step_rocm() {
    if command -v rocminfo &>/dev/null; then
        success "ROCm déjà installé."
        return
    fi

    info "Installation de ROCm..."

    local DEB="amdgpu-install_6.4.60400-1_all.deb"
    local URL="https://repo.radeon.com/amdgpu-install/6.4/ubuntu/noble/${DEB}"

    wget -q --show-progress "$URL" -O "/tmp/${DEB}"
    sudo apt install -y "/tmp/${DEB}"
    sudo amdgpu-install --usecase=rocm --no-dkms -y

    sudo usermod -aG render,video "$USER"

    success "ROCm installé. Un redémarrage est requis pour activer le GPU."
    warn "Lance 'sudo reboot' puis vérifie avec : rocminfo | grep gfx"
}

# =============================================================================
# 4. PARE-FEU (UFW)
# =============================================================================
step_ufw() {
    info "Configuration du pare-feu UFW..."

    sudo ufw allow 22/tcp    # SSH
    sudo ufw allow 80/tcp    # HTTP  (ACME Let's Encrypt)
    sudo ufw allow 443/tcp   # HTTPS
    sudo ufw allow 51820/udp # WireGuard (VPN — phase 3)
    # Ollama — restreint au subnet du réseau Docker llm-net uniquement
    DOCKER_SUBNET=$(docker network inspect llm-server_llm-net 2>/dev/null \
        | grep -oP '"Subnet":\s*"\K[^"]+' | head -1)
    if [[ -n "$DOCKER_SUBNET" ]]; then
        sudo ufw allow from "$DOCKER_SUBNET" to any port 11434
        success "Ollama : accès restreint au subnet Docker ($DOCKER_SUBNET)"
    else
        warn "Réseau llm-net introuvable — démarre la stack avant de relancer cette étape."
    fi

    sudo ufw --force enable
    sudo ufw status verbose
    success "Pare-feu configuré."
}

# =============================================================================
# 5. GÉNÉRATION DU FICHIER .env
# =============================================================================
step_env() {
    local ENV_FILE="${SCRIPT_DIR}/.env"

    if [[ -f "$ENV_FILE" ]]; then
        warn ".env déjà présent — ignoré. Supprime-le manuellement pour le régénérer."
        return
    fi

    info "Génération des secrets et du fichier .env..."

    local NEXTCLOUD_ADMIN_PASSWORD
    while true; do
        read -r -s -p "Mot de passe admin Nextcloud : " NEXTCLOUD_ADMIN_PASSWORD
        echo ""
        read -r -s -p "Confirmer : " NEXTCLOUD_ADMIN_PASSWORD_CONFIRM
        echo ""
        if [[ "$NEXTCLOUD_ADMIN_PASSWORD" == "$NEXTCLOUD_ADMIN_PASSWORD_CONFIRM" ]]; then
            break
        fi
        warn "Les mots de passe ne correspondent pas, réessaie."
    done

    cat > "$ENV_FILE" <<EOF
# Authelia
AUTHELIA_JWT_SECRET=$(openssl rand -hex 32)
AUTHELIA_SESSION_SECRET=$(openssl rand -hex 32)
AUTHELIA_STORAGE_ENCRYPTION_KEY=$(openssl rand -hex 32)

# Open WebUI
WEBUI_SECRET_KEY=$(openssl rand -hex 32)

# Nextcloud
NEXTCLOUD_DB_PASSWORD=$(openssl rand -hex 16)
NEXTCLOUD_DB_ROOT_PASSWORD=$(openssl rand -hex 16)
NEXTCLOUD_ADMIN_USER=Admin
NEXTCLOUD_ADMIN_PASSWORD=${NEXTCLOUD_ADMIN_PASSWORD}
EOF

    chmod 600 "$ENV_FILE"
    success ".env créé avec tous les secrets."
}

# =============================================================================
# 7. HASH BCRYPT AUTHELIA (mot de passe utilisateur hugo)
# =============================================================================
step_authelia_password() {
    info "Génération du hash bcrypt pour le mot de passe Authelia..."
    echo ""
    read -r -s -p "Entre le mot de passe Authelia pour l'utilisateur 'hugo' : " AUTHELIA_PASS
    echo ""

    local HASH
    HASH=$(docker run --rm authelia/authelia:latest \
        authelia crypto hash generate bcrypt --password "$AUTHELIA_PASS" \
        | grep "Digest:" | awk '{print $2}')

    if [[ -z "$HASH" ]]; then
        error "Impossible de générer le hash. Docker est-il démarré ?"
    fi

    sudo chown -R "$USER":"$USER" "${SCRIPT_DIR}/authelia/"

    # Remplacer uniquement le hash de l'utilisateur hugo
    sed -i "/^  hugo:/,/^  [^ ]/ s|password:.*|password: \"${HASH}\"|" \
        "${SCRIPT_DIR}/authelia/users_database.yml"

    success "Hash bcrypt mis à jour pour l'utilisateur hugo."
}

# =============================================================================
# 8. OLLAMA (bare metal — GPU AMD via ROCm — modèles sur /data)
# =============================================================================
step_ollama() {
    if command -v ollama &>/dev/null; then
        success "Ollama déjà installé : $(ollama --version)"
    else
        info "Installation d'Ollama..."
        curl -fsSL https://ollama.com/install.sh | sh
        success "Ollama installé."
    fi

    # Configurer le service systemd
    info "Configuration d'Ollama..."
    sudo mkdir -p /etc/systemd/system/ollama.service.d
    cat <<EOF | sudo tee /etc/systemd/system/ollama.service.d/override.conf > /dev/null
[Service]
Environment="OLLAMA_HOST=0.0.0.0"
Environment="OLLAMA_MODELS=/data/ollama/models"
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable ollama
    sudo systemctl restart ollama

    # Attendre que le service soit prêt
    local RETRIES=10
    until curl -sf http://localhost:11434 &>/dev/null || [[ $RETRIES -eq 0 ]]; do
        sleep 2
        (( RETRIES-- ))
    done

    if ! curl -sf http://localhost:11434 &>/dev/null; then
        error "Ollama ne répond pas sur le port 11434. Vérifie : sudo journalctl -u ollama -n 30"
    fi

    success "Ollama actif sur http://localhost:11434"
    info "GPU détecté :"
    sudo journalctl -u ollama -n 5 --no-pager | grep -i "rocm\|gfx\|vram" || true
    echo ""
    success "Installe tes modèles avec : ollama pull <modele>"
}

# =============================================================================
# 9. DÉMARRAGE DE LA STACK DOCKER COMPOSE
# =============================================================================
step_stack() {
    local ENV_FILE="${SCRIPT_DIR}/.env"

    if [[ ! -f "$ENV_FILE" ]]; then
        error ".env introuvable. Lance d'abord : bash setup.sh env"
    fi

    info "Démarrage de la stack Docker Compose..."
    cd "$SCRIPT_DIR"
    sudo docker compose up -d

    echo ""
    info "État des services :"
    sudo docker compose ps

    echo ""
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}   Stack démarrée avec succès !            ${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""
    echo -e "  ${BLUE}Authelia (SSO)${NC}  →  https://auth.${DOMAIN}"
    echo -e "  ${BLUE}Open WebUI${NC}      →  https://chat.${DOMAIN}"
    echo -e "  ${BLUE}Nextcloud${NC}       →  https://cloud.${DOMAIN}"
    echo -e "  ${BLUE}Portainer${NC}       →  https://portainer.${DOMAIN}"
    echo ""
}

# =============================================================================
# POINT D'ENTRÉE
# =============================================================================
main() {
    local STEP="${1:-all}"

    echo ""
    echo -e "${BLUE}======================================${NC}"
    echo -e "${BLUE}   LLM Server — Setup automatisé     ${NC}"
    echo -e "${BLUE}======================================${NC}"
    echo ""

    case "$STEP" in
        clone)             step_clone ;;
        system)            step_system ;;
        docker)            step_docker ;;
        rocm)              step_rocm ;;
        ufw)               step_ufw ;;
        env)               step_env ;;
        authelia-password) step_authelia_password ;;
        ollama)            step_ollama ;;
        stack)             step_stack ;;
        all)
            step_clone
            step_system
            step_docker
            step_rocm
            step_ufw
            step_env
            step_authelia_password
            step_ollama
            step_stack
            ;;
        *)
            echo "Usage : bash setup.sh [clone|system|docker|rocm|ufw|env|authelia-password|ollama|stack|all]"
            exit 1
            ;;
    esac
}

main "$@"
