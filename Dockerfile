#########################################################
###              Scratch Container Image              ###
#########################################################

FROM centos:centos7 AS scratch


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
RUN groupadd -g 1000 deploy && useradd -u 1000 -g 1000 -c 'Deployment User' -m -d '/home/deploy' -s '/bin/bash' deploy
RUN gpasswd --add deploy wheel
RUN echo "deploy ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/deploy && \
    chmod 0440 /etc/sudoers.d/deploy


# Switch to Non-Root 'deploy' User
USER deploy


### Download/Extract Consul
RUN wget https://releases.hashicorp.com/consul/${CONSUL_VERSION}/consul_${CONSUL_VERSION}_linux_amd64.zip -q -nv -P /home/deploy
RUN sudo unzip /home/deploy/consul_${CONSUL_VERSION}_linux_amd64.zip -d /usr/local/bin/

### Download/Extract Vault
RUN wget https://releases.hashicorp.com/vault/${VAULT_VERSION}/vault_${VAULT_VERSION}_linux_amd64.zip -q -nv -P /home/deploy
RUN sudo unzip /home/deploy/vault_${VAULT_VERSION}_linux_amd64.zip -d /usr/local/bin/
RUN vault -autocomplete-install
RUN exec $SHELL

### Download/Extract Consul-Template
RUN wget https://releases.hashicorp.com/consul-template/${CONSUL_TEMPLATE_VERSION}/consul-template_${CONSUL_TEMPLATE_VERSION}_linux_amd64.zip -q -nv -P /home/deploy
RUN sudo unzip /home/deploy/consul-template_${CONSUL_TEMPLATE_VERSION}_linux_amd64.zip -d /usr/local/bin/

### Download/Extract EnvConsul
RUN wget https://releases.hashicorp.com/envconsul/${ENVCONSUL_VERSION}/envconsul_${ENVCONSUL_VERSION}_linux_amd64.zip -q -nv -P /home/deploy
RUN sudo unzip /home/deploy/envconsul_${ENVCONSUL_VERSION}_linux_amd64.zip -d /usr/local/bin/






###########################################################
###         Deployable Artifact Container Image         ###
###########################################################

FROM centos:centos7

# Download/Install Dependencies
RUN yum install -y epel-release
RUN yum install -y jq sudo git


# Clean Yum Package Cache
RUN yum clean all


# Creat Container Process User
RUN groupadd -g 1000 deploy && useradd -u 1000 -g 1000 -c 'Deployment User' -m -d '/home/deploy' -s '/bin/bash' deploy
RUN gpasswd --add deploy wheel
RUN echo "deploy ALL=(root) NOPASSWD:ALL" > /etc/sudoers.d/deploy && \
    chmod 0440 /etc/sudoers.d/deploy


# Switch to Non-Root 'deploy' User
USER deploy


### Copy Binaries from Scratch Image
COPY --from=scratch /usr/local/bin/consul /usr/local/bin/consul
COPY --from=scratch /usr/local/bin/vault /usr/local/bin/vault
COPY --from=scratch /usr/local/bin/consul-template /usr/local/bin/consul-template
COPY --from=scratch /usr/local/bin/envconsul /usr/local/bin/envconsul


### Stage Project Files in Containers Filesystem
COPY --chown=deploy docker-entrypoint.sh /home/deploy/docker-entrypoint.sh
COPY --chown=deploy fixtures.sh /home/deploy/fixtures.sh
COPY --chown=deploy resume.ctmpl /home/deploy/resume.ctmpl


# Set File Permissions
RUN sudo chmod 755 /home/deploy/docker-entrypoint.sh
RUN sudo chmod 755 /home/deploy/fixtures.sh
RUN sudo chmod 755 /home/deploy/resume.ctmpl


# Set Folder Ownership
RUN sudo chown -R deploy:deploy /home/deploy/


# Enable Vault Autocomplete
RUN vault -autocomplete-install
RUN exec $SHELL


### Start Container
WORKDIR /home/deploy
ENTRYPOINT ["/home/deploy/docker-entrypoint.sh"]
EXPOSE 8500