Vagrant.configure("2") do |config|
  config.vm.box      = "ubuntu/jammy64"
  config.vm.hostname = "devops-essentials-vm"

  # Desabilita o vagrant-vbguest (incompatível com VirtualBox 7.1+)
  config.vbguest.auto_update = false if Vagrant.has_plugin?("vagrant-vbguest")

  config.vm.network "private_network", ip: "192.168.56.10"

  config.vm.provider "virtualbox" do |vb|
    vb.name   = "devops-essentials-vm"
    vb.memory = 8192
    vb.cpus   = 4
    vb.customize ["modifyvm", :id, "--nested-hw-virt", "on"]
  end

  config.vm.provision "shell", inline: <<-SHELL
    set -e
    export DEBIAN_FRONTEND=noninteractive

    echo ">>> Atualizando pacotes..."
    apt-get update -qq && apt-get upgrade -y -qq
    apt-get install -y -qq curl wget git vim jq unzip ca-certificates gnupg apt-transport-https

    echo ">>> Instalando Docker..."
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
      > /etc/apt/sources.list.d/docker.list
    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    usermod -aG docker vagrant
    systemctl enable --now docker

    echo ">>> Instalando kubectl..."
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.32/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.32/deb/ /" \
      > /etc/apt/sources.list.d/kubernetes.list
    apt-get update -qq && apt-get install -y -qq kubectl

    echo ">>> Instalando kind..."
    curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.27.0/kind-linux-amd64
    chmod +x /usr/local/bin/kind

    echo ">>> Instalando helm..."
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

    echo ">>> Instalando OpenTofu..."
    curl --proto '=https' --tlsv1.2 -fsSL https://get.opentofu.org/install-opentofu.sh | bash -s -- --install-method standalone

    echo ">>> Instalando AWS CLI..."
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
    unzip -q /tmp/awscliv2.zip -d /tmp && /tmp/aws/install
    rm -rf /tmp/aws /tmp/awscliv2.zip

    echo ">>> Configurando autocomplete..."
    cat >> /etc/bash.bashrc << 'EOF'
[ -f /usr/share/bash-completion/bash_completion ] && . /usr/share/bash-completion/bash_completion
command -v kubectl &>/dev/null && source <(kubectl completion bash)
command -v kind    &>/dev/null && source <(kind completion bash)
command -v helm    &>/dev/null && source <(helm completion bash)
EOF

    echo ">>> Clonando repositório do lab..."
    sudo -u vagrant git clone https://github.com/4linux/523.git /home/vagrant/523

    echo ""
    echo "============================================"
    echo " VM pronta! Entre com: vagrant ssh"
    echo " Lab em: ~/523"
    echo " Suba o lab: cd ~/523 && bash setup.sh"
    echo "============================================"
  SHELL
end
