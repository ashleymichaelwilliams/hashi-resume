#########################################################
###              Scratch Container Image              ###
#########################################################
# Alpine-based stage: downloads and extracts HashiCorp
# binaries so they can be copied into the final image.
#########################################################

FROM alpine:latest AS builder

# Set Env Variables
ENV HASHICORP_RELEASES=https://releases.hashicorp.com
ENV CONSUL_VERSION=1.6.2
ENV VAULT_VERSION=1.2.3
ENV CONSUL_TEMPLATE_VERSION=0.22.0
ENV ENVCONSUL_VERSION=0.9.2


# Download/Install Dependencies
RUN apk add --no-cache wget unzip


### Download/Extract Consul
RUN wget https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip -q -nv -P /tmp && \
    unzip /tmp/consul_${CONSUL_VERSION}_linux_amd64.zip -d /usr/local/bin/ && \
    rm -f /tmp/consul_${CONSUL_VERSION}_linux_amd64.zip

### Download/Extract Vault
RUN wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip -q -nv -P /tmp && \
    unzip /tmp/vault_${VAULT_VERSION}_linux_amd64.zip -d /usr/local/bin/ && \
    rm -f /tmp/vault_${VAULT_VERSION}_linux_amd64.zip

### Download/Extract Consul-Template
RUN wget https://releases.hashicorp.com/consul-template/${CONSUL_TEMPLATE_VERSION}/consul-template_${CONSUL_TEMPLATE_VERSION}_linux_amd64.zip -q -nv -P /tmp && \
    unzip /tmp/consul-template_${CONSUL_TEMPLATE_VERSION}_linux_amd64.zip -d /usr/local/bin/ && \
    rm -f /tmp/consul-template_${CONSUL_TEMPLATE_VERSION}_linux_amd64.zip

### Download/Extract EnvConsul
RUN wget https://releases.hashicorp.com/envconsul/${ENVCONSUL_VERSION}/envconsul_${ENVCONSUL_VERSION}_linux_amd64.zip -q -nv -P /tmp && \
    unzip /tmp/envconsul_${ENVCONSUL_VERSION}_linux_amd64.zip -d /usr/local/bin/ && \
    rm -f /tmp/envconsul_${ENVCONSUL_VERSION}_linux_amd64.zip


###########################################################
###         Deployable Artifact Container Image         ###
###########################################################

FROM alpine:latest

ARG USER=alpine
ENV HOME=/home/$USER


# Download/Install Dependencies
RUN apk update && \
    apk upgrade && \
    apk add bash
RUN apk add --no-cache jq sudo

# Clean Apk Package Cache
RUN rm -rf /var/cache/apk/*


# Creat Container Process User
RUN addgroup -S -g 1000 $USER && \
    adduser -D -S -s '/bin/bash' -h $HOME -u 1000 -G $USER $USER
RUN echo "$USER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/$USER && \
    chmod 0440 /etc/sudoers.d/$USER


# Fix for Sudo Module
RUN echo "Set disable_coredump false" > /etc/sudo.conf


# Switch to Non-Root User
USER $USER
RUN touch $HOME/.bashrc


### Copy Binaries from Builder Image
COPY --from=builder /usr/local/bin/consul /usr/local/bin/consul
COPY --from=builder /usr/local/bin/vault /usr/local/bin/vault
COPY --from=builder /usr/local/bin/consul-template /usr/local/bin/consul-template
COPY --from=builder /usr/local/bin/envconsul /usr/local/bin/envconsul


### Stage Project Files in Containers Filesystem
COPY --chown=$USER docker-entrypoint.sh /docker-entrypoint.sh
COPY --chown=$USER fixtures.sh $HOME/fixtures.sh
COPY --chown=$USER resume.ctmpl $HOME/resume.ctmpl


# Set File Permissions
RUN sudo chmod 755 /docker-entrypoint.sh
RUN sudo chmod 755 $HOME/fixtures.sh
RUN sudo chmod 755 $HOME/resume.ctmpl


# Set Folder Ownership
RUN sudo chown -R $USER:$USER $HOME


# Enable Vault Autocomplete
RUN vault -autocomplete-install
RUN exec $SHELL


### Start Container
WORKDIR $HOME
ENTRYPOINT ["/docker-entrypoint.sh"]
EXPOSE 8500
