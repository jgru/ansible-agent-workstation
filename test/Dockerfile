# What a fresh Debian 13 looks like when a root password was set in the installer:
# an ordinary user, SSH, and neither sudo nor Python. This is the hardest starting
# point for the playbook. The usernames and passwords are test fixtures.
FROM debian:13

RUN apt-get update \
    && apt-get install -y --no-install-recommends openssh-server \
    && apt-get clean && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash nuc \
    && echo 'nuc:nuc-password' | chpasswd \
    && echo 'root:root-password' | chpasswd \
    && mkdir -p /run/sshd

CMD ["/usr/sbin/sshd", "-D", "-e"]
