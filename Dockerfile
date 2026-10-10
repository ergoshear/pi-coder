FROM fedora:44

# Install Node.js (v22+ required), npm, Git, and system utilities
RUN dnf update -y && \
    dnf install -y \
        nodejs \
        npm \
        git \
        curl \
        ca-certificates \
        cockpit \
        dbus-daemon \
        openssh-server \
        sudo \
        systemd && \
    dnf clean all

RUN useradd --create-home --shell /bin/bash pi && \
    install -d -o pi -g pi /workspace && \
    printf 'pi ALL=(ALL) NOPASSWD: ALL\n' > /etc/sudoers.d/pi && \
    chmod 0440 /etc/sudoers.d/pi && \
    visudo --check

# Set workspace directory for the agent
WORKDIR /workspace

# Install Pi Coding Agent globally
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

COPY cockpit.conf /etc/cockpit/cockpit.conf
COPY sshd.conf /etc/ssh/sshd_config.d/00-pi-coder.conf
COPY sshd.pam /etc/pam.d/sshd
COPY entrypoint.sh /usr/local/bin/pi-coder-entrypoint
RUN chmod 0755 /usr/local/bin/pi-coder-entrypoint && \
    systemctl set-default multi-user.target && \
    systemctl enable cockpit.socket sshd.service

ENV container=docker
STOPSIGNAL SIGRTMIN+3
EXPOSE 9090
ENTRYPOINT ["/usr/local/bin/pi-coder-entrypoint"]