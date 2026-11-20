#!/usr/bin/env bash
# Termax (SSH client) access to this Codespace, via Tailscale.
# Runs on every Codespace start (postStartCommand in devcontainer.json).
# Idempotent. Log: /tmp/setup-ssh.log
set -u
exec >>/tmp/setup-ssh.log 2>&1
echo "=== setup-ssh $(date -Is) ==="
cd "$(dirname "$0")/.." || exit 0

# --- authorized_keys (public keys listed in .devcontainer/authorized_keys) ---
if [ -s .devcontainer/authorized_keys ]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  grep -E '^(ssh-|ecdsa-)' .devcontainer/authorized_keys > ~/.ssh/authorized_keys || true
  chmod 600 ~/.ssh/authorized_keys 2>/dev/null || true
fi

# --- sshd on port 2222, key auth only ---
if ! command -v sshd >/dev/null 2>&1; then
  sudo apt-get update -y && sudo apt-get install -y openssh-server || true
fi
if command -v sshd >/dev/null 2>&1; then
  sudo mkdir -p /run/sshd /var/lib/tailscale
  sudo ssh-keygen -A >/dev/null 2>&1 || true
  if ! pgrep -f 'sshd.*2222' >/dev/null 2>&1; then
    sudo /usr/sbin/sshd -p 2222 -o PasswordAuthentication=no -o PermitRootLogin=no || true
  fi
fi

# --- Tailscale in userspace-networking mode (Codespaces has no /dev/net/tun) ---
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh || true
fi
if command -v tailscale >/dev/null 2>&1; then
  SOCK=/tmp/tailscaled.sock
  if ! pgrep -f 'tailscaled.*userspace-networking' >/dev/null 2>&1; then
    nohup sudo tailscaled --tun=userspace-networking --socket="$SOCK" --state=/var/lib/tailscale/tailscaled.state >/tmp/tailscaled.log 2>&1 &
    sleep 3
  fi
  if [ -n "${TS_AUTHKEY:-}" ]; then
    sudo tailscale --socket="$SOCK" up --authkey="$TS_AUTHKEY" --hostname=omuretsu-codespace --accept-dns=false || true
  else
    echo 'TS_AUTHKEY is not set: run `tailscale up` once in this Codespace terminal and open the printed URL to authorise this machine, or set the TS_AUTHKEY Codespaces secret.'
    sudo tailscale --socket="$SOCK" up --hostname=omuretsu-codespace --accept-dns=false || true
  fi
  sudo tailscale --socket="$SOCK" status || true
fi
echo '=== setup-ssh done ==='
