#!/usr/bin/env bash
# Run setup.sh against a throwaway Debian 13 container, twice, and fail if the
# second run changes anything. Nothing touches your ~/.ssh.
#
#   test/run.sh                                  x86_64, like the NUC
#   test/run.sh -e dblp_prefetch_index=false     skip the 1.3 GB download
#   PLATFORM=linux/arm64 test/run.sh             native on Apple Silicon
#   LOGIN=root test/run.sh                       start like a VPS, with only root
set -euo pipefail

platform=${PLATFORM:-linux/amd64}
port=${PORT:-2222}
login=${LOGIN:-nuc}
name=setup-test-$$

cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

ssh-keygen -q -t ed25519 -N '' -f "$work/key"
printf 'root-password\n' > "$work/become"

cat > "$work/ssh_config" <<EOF
Host nuc-test
  HostName 127.0.0.1
  Port $port
  User nuc
  IdentityFile $work/key
  IdentitiesOnly yes
  UserKnownHostsFile /dev/null
  StrictHostKeyChecking no
  LogLevel ERROR
EOF

# setup.sh and Ansible both find ssh on PATH, so this reaches them without any
# test-only option in setup.sh.
mkdir "$work/bin"
cat > "$work/bin/ssh" <<EOF
#!/bin/sh
exec /usr/bin/ssh -F "$work/ssh_config" "\$@"
EOF
chmod +x "$work/bin/ssh"
export PATH="$work/bin:$PATH"
export ANSIBLE_BECOME_PASSWORD_FILE="$work/become"

docker build --quiet --platform "$platform" -t setup-test test >/dev/null
# NET_ADMIN lets the firewall load its rules, as it can on a real machine.
docker run -d --platform "$platform" --cap-add NET_ADMIN --name "$name" \
  -p "127.0.0.1:$port:22" setup-test >/dev/null

case "$login" in
  nuc)
    target=nuc-test owner=nuc keys=/home/nuc/.ssh
    ;;
  root)
    # Only root, with a key, as many VPSes start out. The setup must create the
    # user, named nuc so that the checks below log in as it.
    docker exec "$name" userdel --remove nuc 2>/dev/null
    target=root@nuc-test owner=root keys=/root/.ssh
    set -- -e login_user=nuc "$@"
    ;;
  *)
    echo "LOGIN must be nuc or root" >&2
    exit 2
    ;;
esac
docker exec "$name" install -d -o "$owner" -g "$owner" -m 700 "$keys"
docker cp "$work/key.pub" "$name:$keys/authorized_keys"
docker exec "$name" chown "$owner:$owner" "$keys/authorized_keys"

echo "==> First run"
./setup.sh "$target" "$@"

echo "==> Second run, which must change nothing"
./setup.sh "$target" "$@" | tee "$work/second.log"
if ! grep -Eq 'changed=0 +unreachable=0 +failed=0' "$work/second.log"; then
  echo "FAIL: the second run changed something" >&2
  exit 1
fi

echo "==> A login shell finds the tools"
ssh nuc-test 'bash -lc "claude --version && codex --version && herdr --version"'
echo "==> Non-interactive ssh finds them too"
ssh nuc-test 'herdr --version'

# Probed from a second container: the firewall lets the machine itself in, and
# through the published port Docker's proxy would answer instead. A dropped
# connection times out (124), where a closed port is refused at once (1).
echo "==> The firewall lets SSH in and drops everything else"
ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$name")
probe() {
  local rc=0
  docker run --rm --platform "$platform" debian:13 \
    timeout 5 bash -c "</dev/tcp/$ip/$1" 2>/dev/null || rc=$?
  echo "$rc"
}
rc=$(probe 22)
[ "$rc" = 0 ] || { echo "FAIL: SSH didn't connect (exit $rc)" >&2; exit 1; }
rc=$(probe 8000)
[ "$rc" = 124 ] || { echo "FAIL: port 8000 wasn't dropped (exit $rc)" >&2; exit 1; }

echo "PASS"
