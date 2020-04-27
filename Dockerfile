#########################################################
###              Scratch Container Image              ###
#########################################################

FROM centos:centos7 AS scratch

ARG USER=centos
ENV HOME=/home/$USER

# Set Env Variables
ENV HASHICORP_RELEASES=https://releases.hashicorp.com
ENV CONSUL_VERSION=1.6.2
ENV VAULT_VERSION=1.2.3
ENV CONSUL_TEMPLATE_VERSION=0.22.0
ENV ENVCONSUL_VERSION=0.9.2


# Download/Install Dependencies
RUN yum install -y epel-release
RUN yum install -y unzip jq wget which sudo git


# Creat Container Process User
RUN groupadd -g 1000 $USER && useradd -u 1000 -g 1000 -m -d $HOME -s '/bin/bash' $USER
RUN gpasswd --add $USER wheel
RUN echo "$USER ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/$USER && \
    chmod 0440 /etc/sudoers.d/$USER


# Switch to Non-Root User
USER $USER


### Download/Extract Consul
RUN wget https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip -q -nv -P $HOME
RUN sudo unzip $HOME/consul_${CONSUL_VERSION}_linux_amd64.zip -d /usr/local/bin/

### Download/Extract Vault
RUN wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip -q -nv -P $HOME
RUN sudo unzip $HOME/vault_${VAULT_VERSION}_linux_amd64.zip -d /usr/local/bin/

### Download/Extract Consul-Template
RUN wget https://releases.hashicorp.com/consul-template/${CONSUL_TEMPLATE_VERSION}/consul-template_${CONSUL_TEMPLATE_VERSION}_linux_amd64.zip -q -nv -P $HOME
RUN sudo unzip $HOME/consul-template_${CONSUL_TEMPLATE_VERSION}_linux_amd64.zip -d /usr/local/bin/

### Download/Extract EnvConsul
RUN wget https://releases.hashicorp.com/envconsul/${ENVCONSUL_VERSION}/envconsul_${ENVCONSUL_VERSION}_linux_amd64.zip -q -nv -P $HOME
RUN sudo unzip $HOME/envconsul_${ENVCONSUL_VERSION}_linux_amd64.zip -d /usr/local/bin/






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

# Clean Yum Package Cache
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


### Copy Binaries from Scratch Image
COPY --from=scratch /usr/local/bin/consul /usr/local/bin/consul
COPY --from=scratch /usr/local/bin/vault /usr/local/bin/vault
COPY --from=scratch /usr/local/bin/consul-template /usr/local/bin/consul-template
COPY --from=scratch /usr/local/bin/envconsul /usr/local/bin/envconsul


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
