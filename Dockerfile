FROM fedora:44

# Install Node.js (v22+ required), npm, Git, and system utilities
RUN dnf update -y && \
    dnf install -y \
        nodejs \
        npm \
        git \
        curl \
        ca-certificates && \
    dnf clean all

# Set workspace directory for the agent
WORKDIR /workspace

# Install Pi Coding Agent globally
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent

# Default entrypoint for Pi agent
ENTRYPOINT ["pi"]