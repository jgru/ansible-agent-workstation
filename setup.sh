#!/usr/bin/env bash
# Set up or update a Debian 13 machine for agent-driven development.
#
#   ./setup.sh [user@]host             first run, and any re-run
#   ./setup.sh root@host               where only root exists: creates your user
#   ./setup.sh [user@]host update      upgrade everything already installed
#   ./setup.sh localhost               run on the machine itself, not as root
#
# Further arguments go to ansible-playbook, e.g. --tags mcp or -e latex_enabled=true.
set -euo pipefail

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
[ $# -ge 1 ] || usage
case "$1" in -h|--help) usage ;; esac

target=$1
shift
playbook=site.yml
if [ "${1:-}" = update ]; then
  playbook=update.yml
  shift
fi

cd "$(dirname "$0")"

if [ ! -x .venv/bin/ansible-playbook ]; then
  echo "==> Installing Ansible into .venv"
  python3 -m venv .venv
  .venv/bin/pip install --quiet --disable-pip-version-check -r requirements.txt
fi

if [ "$target" = localhost ]; then
  args=(-i localhost, -c local)
  on_target() { bash -c "$1"; }
else
  case "$target" in
    *@*) args=(-i "${target#*@}," -u "${target%%@*}") ;;
    *)   args=(-i "$target,") ;;
  esac
  ssh_opts=(-o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new)
  if ! ssh "${ssh_opts[@]}" "$target" true 2>/dev/null; then
    echo "==> No SSH key login yet. Copying your key over; enter the password for $target."
    ssh-copy-id -o StrictHostKeyChecking=accept-new "$target"
  fi
  on_target() { ssh "${ssh_opts[@]}" "$target" "$1"; }
fi

# Logged in as root, the playbook creates the login user with passwordless sudo
# and carries on as that user, so it needs no password. On the machine itself it
# can't change user.
if [ "$(on_target 'id -u')" = 0 ]; then
  if [ "$target" = localhost ]; then
    echo "Run this as your own user, not root, or the agents would run as root." >&2
    echo "Create one (adduser NAME && adduser NAME sudo), log in as them and run it again," >&2
    echo "or run it from your laptop as: ./setup.sh root@<this machine>" >&2
    exit 1
  fi
  echo "==> Logged in as root. The setup continues as your own user, creating it if needed."
# The Debian installer leaves sudo out entirely if a root password was set, so
# the first run may have to go through su. The playbook then sets up sudo.
elif ! on_target 'sudo -n true' 2>/dev/null; then
  if on_target 'command -v sudo >/dev/null && id -nG | grep -qw sudo'; then
    echo "==> Enter your sudo password below (BECOME password). Later runs won't ask."
  else
    echo "==> This user can't sudo yet. Enter the ROOT password below (BECOME password). Later runs won't ask."
    args+=(-e bootstrap_become_method=su)
  fi
  [ -n "${ANSIBLE_BECOME_PASSWORD_FILE:-}" ] || args+=(--ask-become-pass)
fi

if head -n 1 group_vars/all/secrets.yml 2>/dev/null | grep -q '^\$ANSIBLE_VAULT'; then
  args+=(--ask-vault-pass)
fi

exec .venv/bin/ansible-playbook "${args[@]}" "$playbook" "$@"
