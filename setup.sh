#!/usr/bin/env bash
# One-time setup of the Cora workspace on this laptop.
#
# Run on the HOST (not inside the container), from anywhere:
#   ~/dev/cora/cora_ws/setup.sh                 # desktop/simulation (desktop.repos)
#   ~/dev/cora/cora_ws/setup.sh robot.repos     # real-robot packages
#
# What it does:
#   1. Checks the prerequisites and tells you what's missing.
#   2. Writes .env with this laptop's settings (user ID, GPU group, NVIDIA).
#   3. Downloads the repos into src/ (repos that already exist are left alone).
#   4. Builds the Docker image.
# Safe to run again: it never deletes anything or overwrites your changes.

set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"
REPOS_FILE="${1:-desktop.repos}"

bold() { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✔\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
bad()  { printf '  \033[31m✘\033[0m %s\n' "$*"; MISSING=1; }

# --------------------------------------------------------------------------
bold "1/4 Checking prerequisites"
# --------------------------------------------------------------------------
MISSING=0

if [ -f /.dockerenv ]; then
  echo "You are inside a container. Run setup.sh on the host (a normal terminal)."
  exit 1
fi
if [ "$(id -u)" -eq 0 ]; then
  echo "Don't run setup.sh with sudo or as root; run it as your normal user."
  exit 1
fi
if [ ! -f "$REPOS_FILE" ]; then
  echo "Repos file '$REPOS_FILE' not found in $(pwd)."
  exit 1
fi

if ! command -v docker >/dev/null; then
  bad "Docker is not installed. See https://docs.docker.com/engine/install/ubuntu/"
elif ! docker info >/dev/null 2>&1; then
  if id -nG | grep -qw docker; then
    bad "Docker is installed but not reachable. Is it running? Try: sudo systemctl start docker"
  else
    bad "Your user can't use Docker yet. Run: sudo usermod -aG docker \$USER   then log out and back in."
  fi
else
  ok "Docker $(docker version --format '{{.Server.Version}}')"
  if docker compose version >/dev/null 2>&1; then
    ok "Docker Compose $(docker compose version --short)"
  else
    bad "The Docker Compose plugin is missing. Run: sudo apt install docker-compose-plugin"
  fi
fi

if command -v git >/dev/null; then ok "git"; else bad "git is missing. Run: sudo apt install git"; fi

if command -v vcs >/dev/null; then
  ok "vcstool"
else
  bad "vcstool is missing. Run: sudo apt install python3-vcstool   (or: sudo apt install vcstool)"
fi

# The .repos files clone over SSH. GitHub answers a successful login with
# "successfully authenticated" and exit code 1 (it doesn't offer a shell).
if grep -q 'git@github.com' "$REPOS_FILE"; then
  SSH_REPLY="$(ssh -T -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
                 git@github.com 2>&1 || true)"
  if [[ "$SSH_REPLY" == *"successfully authenticated"* ]]; then
    ok "GitHub SSH access"
  else
    bad "No GitHub SSH access. Set up a key: https://docs.github.com/en/authentication/connecting-to-github-with-ssh"
  fi
fi

if [ -z "${DISPLAY:-}" ]; then
  warn "DISPLAY is not set. Setup works, but start the container from a desktop terminal (not SSH) or windows won't open."
fi

if [ "$MISSING" -ne 0 ]; then
  echo
  echo "Fix the items marked ✘ above, then run ./setup.sh again."
  exit 1
fi

# --------------------------------------------------------------------------
bold "2/4 Machine settings (.env)"
# --------------------------------------------------------------------------
if [ -f .env ]; then
  ok ".env already exists; keeping it. Delete it and rerun setup.sh to regenerate."
  if ! grep -qx "USER_UID=$(id -u)" .env; then
    warn ".env has a different USER_UID than your user ($(id -u)). Files may end up owned by someone else."
  fi
else
  RENDER_GID="$(getent group render | cut -d: -f3 || true)"
  {
    echo "# Machine-specific settings for compose.yaml, written by setup.sh."
    echo "USER_UID=$(id -u)"
    echo "USER_GID=$(id -g)"
    if [ -n "$RENDER_GID" ]; then echo "RENDER_GID=$RENDER_GID"; fi
  } > .env
  ok "User ID $(id -u), group ID $(id -g)"
  if [ -n "$RENDER_GID" ]; then
    ok "GPU render group ID $RENDER_GID"
  else
    warn "No 'render' group on this machine; graphics may fall back to (slow) software rendering."
  fi

  # NVIDIA: only if Docker has the NVIDIA runtime (NVIDIA Container Toolkit).
  if docker info 2>/dev/null | grep -qi nvidia; then
    {
      echo "# Docker supports NVIDIA here: always include the GPU override."
      echo "COMPOSE_FILE=compose.yaml:compose.nvidia.yaml"
    } >> .env
    ok "NVIDIA GPU support detected; enabled compose.nvidia.yaml"
  elif command -v nvidia-smi >/dev/null; then
    warn "NVIDIA GPU found, but Docker can't use it. Install the NVIDIA Container Toolkit and rerun (after deleting .env) to enable it."
  else
    ok "No NVIDIA GPU support; using Intel/AMD graphics"
  fi
fi

# --------------------------------------------------------------------------
bold "3/4 Downloading repos from $REPOS_FILE into src/"
# --------------------------------------------------------------------------
mkdir -p src
# --skip-existing: never touch repos you already have (your branches and
# uncommitted changes are safe). No --recursive: see README.
vcs import --skip-existing src < "$REPOS_FILE"
ok "Repos in src/: $(cd src && ls -d */ | tr -d / | tr '\n' ' ')"

# --------------------------------------------------------------------------
bold "4/4 Building the Docker image (first time: ~6 GB download, 5-10 minutes)"
# --------------------------------------------------------------------------
docker compose build
ok "Image $(docker compose config --images | head -1) is ready"

bold "Setup complete. Next:"
cat <<EOF
  cd $(pwd)
  docker compose up -d             # start the container
  docker compose exec dev bash     # open a terminal inside it
  colcon build --symlink-install   # (inside the container) build the workspace

  See README.md, Part 2, for the daily workflow.
EOF
