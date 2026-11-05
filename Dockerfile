FROM fedora:latest

RUN dnf copr enable -y elegos/gitflow
RUN dnf install -y gitflow cargo npm awscli2 which procps-ng jq
RUN groupadd -g 130 sudo && echo "%sudo        ALL=(ALL)       NOPASSWD: ALL" > /etc/sudoers.d/00-sudo-nopasswd
RUN groupadd -g 1000 aicode && useradd -m -u 1000 -g 1000 -G sudo aicode
USER 1000
VOLUME /home/aicode/Projects
WORKDIR /home/aicode

RUN mkdir -p ~/.ssh
ENV GIT_EMAIL="agents-containers-harness@geek.co.il" GIT_NAME="Change Me!"

# install Claude CLI
ENV CLAUDE_CONFIG_DIR="/home/aicode/.config/claude" PATH="/home/aicode/.local/bin:$PATH"
RUN curl -fsSL https://claude.ai/install.sh | bash
RUN claude install

# install Opencode CLI
RUN curl -fsSL https://opencode.ai/v2/install | bash

VOLUME /home/aicode/.config
ADD default.conf /.env
ADD docker-entrypoint.sh /docker-entrypoint.sh
CMD [ "/docker-entrypoint.sh" ]
