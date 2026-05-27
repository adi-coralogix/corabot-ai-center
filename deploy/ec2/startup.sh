#!/usr/bin/env bash
# EC2 user-data — runs as root on first boot.
# Terraform renders this file via templatefile(), injecting:
#   secret_arn  — ARN of the Secrets Manager secret that holds all .env values
#   region      — AWS region
set -euo pipefail

SECRET_ARN="${secret_arn}"
REGION="${region}"
REPO_URL="https://github.com/adi-coralogix/corabot-ai-center.git"
APP_DIR="/opt/corabot-ai-center"
LOG="/var/log/corabot-startup.log"

exec > >(tee -a "$LOG") 2>&1
echo "[$(date -u +%FT%TZ)] ── corabot-ai-center first-boot setup ──"

# ── 1. System packages ────────────────────────────────────────────────────────
echo "[$(date -u +%FT%TZ)] Installing system packages..."
dnf update -y
dnf install -y docker git jq

# ── 2. Docker service ─────────────────────────────────────────────────────────
systemctl enable --now docker
usermod -aG docker ec2-user

# ── 3. Docker Compose v2 plugin ───────────────────────────────────────────────
echo "[$(date -u +%FT%TZ)] Installing Docker Compose plugin..."
COMPOSE_VERSION=$(curl -fsSL https://api.github.com/repos/docker/compose/releases/latest \
  | jq -r '.tag_name')
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL \
  "https://github.com/docker/compose/releases/download/$${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
docker compose version

# ── 4. Clone repository ───────────────────────────────────────────────────────
echo "[$(date -u +%FT%TZ)] Cloning repository..."
git clone "$REPO_URL" "$APP_DIR"

# ── 5. Fetch secrets → write .env ─────────────────────────────────────────────
# The instance IAM role grants secretsmanager:GetSecretValue on this secret only.
# No static credentials are stored on disk or in the image.
echo "[$(date -u +%FT%TZ)] Fetching secrets from Secrets Manager ($SECRET_ARN)..."
SECRET_JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_ARN" \
  --region "$REGION" \
  --query SecretString \
  --output text)

# Convert {"KEY":"value",...} → KEY=value .env lines
jq -r 'to_entries[] | "\(.key)=\(.value)"' <<< "$SECRET_JSON" > "$APP_DIR/.env"
chmod 600 "$APP_DIR/.env"
echo "[$(date -u +%FT%TZ)] .env written ($(wc -l < "$APP_DIR/.env") vars)."

# ── 6. Build and start the stack ─────────────────────────────────────────────
echo "[$(date -u +%FT%TZ)] Starting docker compose stack..."
cd "$APP_DIR"
docker compose up -d --build

# ── 7. Install systemd unit for auto-restart on reboot ───────────────────────
cat > /etc/systemd/system/corabot.service <<'UNIT'
[Unit]
Description=CoraBot AI Center (docker compose)
Requires=docker.service
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/corabot-ai-center
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
TimeoutStartSec=300

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable corabot.service

echo "[$(date -u +%FT%TZ)] ── Setup complete. Stack is up. ──"
echo "[$(date -u +%FT%TZ)] Check health: docker compose -f $APP_DIR/docker-compose.yml ps"
