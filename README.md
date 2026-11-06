# Agent workstation setup

Ansible that turns a fresh Debian 13 machine, such as an Intel NUC or a VPS, into
a ready environment for agent-driven development.

| Area | What you get |
|---|---|
| Editor | Emacs (`emacs-nox`) |
| Agents | Claude Code, Codex, [herdr](https://herdr.dev) with its integrations for both |
| Git hosting | An SSH key for the machine, pinned GitHub and GitLab host keys, `gh`, `glab`, your git identity |
| MCP servers, in both agents | [mcp-dblp](https://github.com/szeider/mcp-dblp) with its local index, [Google Scholar](https://github.com/JackKuo666/Google-Scholar-MCP-Server) |
| Spec-driven development, in both agents | [Superpowers](https://github.com/obra/superpowers) (lightweight), [GSD Core](https://github.com/open-gsd/gsd-core) (comprehensive) |
| Base | Node.js 24, uv, the build tools and utilities from the container image, sleep and suspend disabled |
| Network | A firewall that lets in only SSH |

## Quick start

1. Install Debian 13 on the NUC. In the installer's software selection, tick
   **SSH server**. Note the username you create.
2. From your laptop, which only needs `python3`:

   ```bash
   ./setup.sh user@192.168.1.50
   ```

   The first run copies your SSH key over if needed and asks for a password once:
   your sudo password, or the root password if you set one in the installer. A first
   run takes a while, mostly for the DBLP index download.

3. It finishes by checking that everything runs, then lists what only you can do:
   logging in to Claude Code and Codex, and adding the machine's key to GitHub and
   GitLab if you gave it no tokens.

Run it again whenever you like: it only changes what is missing.

**On a VPS that gives you only root**, run `./setup.sh root@203.0.113.7`. The
agents shouldn't run as root, so the setup creates a user with the same name as
yours on the laptop (`login_user`), lets root's SSH keys log in as it with
passwordless sudo, and sets everything up for that user. Log in as that user from
then on.

To run it on the NUC itself instead, get this directory onto it and then, as your
own user rather than root:

```bash
sudo apt install python3-venv
./setup.sh localhost
```

## Updating

```bash
./setup.sh user@192.168.1.50 update
```

This upgrades the system packages and every installed tool, including the monthly
DBLP index. Claude Code also updates itself in the background.

## GitHub and GitLab access

The machine gets its own passphrase-free SSH key, so agents can keep working after
you disconnect. To have `gh` and `glab` logged in and the key uploaded for you, pass
tokens:

```bash
SETUP_GITHUB_TOKEN=... SETUP_GITLAB_TOKEN=... ./setup.sh user@192.168.1.50
```

Or copy `secrets.example.yml` to `group_vars/all/secrets.yml`. That file lists the
token scopes needed. Tokens are stored on the machine by `gh` and `glab`, where any
agent can read them, so give them no more access than your agents should have.

Without tokens, the final summary prints the key and where to paste it. You can log
the CLIs in later with `gh auth login` and `glab auth login`.

For a self-hosted GitLab, set `gitlab_host`. Its host key is trusted on first use,
because it can't be pinned in advance.

## Configuration

Settings are in `group_vars/all/main.yml`, including:

| Setting | Default | |
|---|---|---|
| `emacs_package` | `emacs-nox` | Use `emacs` if the machine has a desktop |
| `latex_enabled` | `true` | Installs `texlive-full`, several GB |
| `extra_packages` | `[]` | More apt packages |
| `passwordless_sudo` | `true` | See below |
| `login_user` | your username | The user created when you connect as root |
| `firewall_enabled` | `true` | See below |
| `firewall_open_ports` | `[]` | Ports besides SSH anyone may reach, as `443/tcp` |
| `firewall_trusted_networks` | `[]` | Networks that may reach every port, such as your LAN |
| `dblp_prefetch_index` | `true` | Needs about 5.5 GB free |
| `mcp_servers` | | Add servers here to register them with both agents |

Override anything for one run with `-e`, or run part of the setup with
`--tags base,firewall,agents,git,mcp,spec`.

**Passwordless sudo.** It is on so that re-runs need no password and agents can
install packages, as in the container image this was modelled on. Outside a
container, it also means any agent can become root on the machine.

**Firewall.** Incoming connections are dropped except SSH, on the ports sshd
listens on and the one the setup connects through. Agents start dev servers that
listen on every address, and on a VPS that would put them on the internet. To open
one from your laptop, forward it over SSH:
`ssh -L 3000:localhost:3000 user@host`. On a NUC you can instead add your LAN to
`firewall_trusted_networks`.


## Testing

`test/run.sh` runs the whole setup twice against a throwaway Debian 13 container that
starts with no sudo and no Python. It fails if the second run changes anything, or
if the firewall lets anything but SSH in. It needs Docker, and defaults to x86_64 to
match the NUC.

```bash
test/run.sh -e dblp_prefetch_index=false
```

`LOGIN=root` starts it like a VPS instead, with only root, so the setup has to
create the user.

On Apple Silicon, Docker's qemu emulation of x86_64 has no AVX2, which Claude Code
needs, so test natively there:

```bash
PLATFORM=linux/arm64 test/run.sh -e dblp_prefetch_index=false
```
