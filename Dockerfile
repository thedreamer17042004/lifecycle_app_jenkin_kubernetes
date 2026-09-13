FROM jenkins/jenkins:lts

USER root

# ==========================================
# Basic packages
# ==========================================
RUN apt-get update && \
    apt-get install -y \
        wget \
        curl \
        gnupg \
        ca-certificates \
        lsb-release \
        git \
        unzip \
        jq \
        python3 \
        python3-pip \
        python3-venv && \
    rm -rf /var/lib/apt/lists/*


# ==========================================
# Docker CLI
# ==========================================
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg \
      -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
      https://download.docker.com/linux/debian \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      > /etc/apt/sources.list.d/docker.list && \
    apt-get update && \
    apt-get install -y docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*


# ==========================================
# Trivy
# ==========================================
RUN wget -qO - \
      https://aquasecurity.github.io/trivy-repo/deb/public.key \
      | gpg --dearmor \
      -o /usr/share/keyrings/trivy.gpg && \
    echo \
      "deb [signed-by=/usr/share/keyrings/trivy.gpg] \
      https://aquasecurity.github.io/trivy-repo/deb generic main" \
      > /etc/apt/sources.list.d/trivy.list && \
    apt-get update && \
    apt-get install -y trivy && \
    rm -rf /var/lib/apt/lists/*


# ==========================================
# kubectl
# ==========================================
ARG KUBECTL_VERSION=v1.32.2

RUN curl -LO \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    install -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl


# ==========================================
# Semgrep CLI
# ==========================================
RUN python3 -m venv /opt/semgrep && \
    /opt/semgrep/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/semgrep/bin/pip install --no-cache-dir semgrep && \
    chown -R jenkins:jenkins /opt/semgrep && \
    ln -s /opt/semgrep/bin/semgrep /usr/local/bin/semgrep


# ==========================================
# Terraform CLI
# ==========================================
ARG TERRAFORM_VERSION=1.13.1

RUN curl -fsSL \
      "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
      -o /tmp/terraform.zip && \
    unzip /tmp/terraform.zip -d /usr/local/bin && \
    chmod +x /usr/local/bin/terraform && \
    chown jenkins:jenkins /usr/local/bin/terraform && \
    rm -f /tmp/terraform.zip


# ==========================================
# Terraform directories
# ==========================================
RUN mkdir -p /home/jenkins/.terraform.d/plugin-cache && \
    chown -R jenkins:jenkins /home/jenkins/.terraform.d


# ==========================================
# Jenkins working directories
# ==========================================
RUN mkdir -p /home/jenkins/workspace && \
    chown -R jenkins:jenkins /home/jenkins/workspace


# ==========================================
# Verify tools as Jenkins user
# ==========================================
RUN su -s /bin/bash jenkins -c "docker --version" && \
    su -s /bin/bash jenkins -c "trivy --version" && \
    su -s /bin/bash jenkins -c "kubectl version --client" && \
    su -s /bin/bash jenkins -c "semgrep --version" && \
    su -s /bin/bash jenkins -c "terraform version"


# ==========================================
# Switch back to Jenkins user
# ==========================================
USER jenkins