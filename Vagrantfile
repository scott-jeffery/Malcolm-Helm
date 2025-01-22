# -*- mode: ruby -*-
# vi: set ft=ruby :

require 'pathname'

# Since 'vagrant up' can be called from any subdirectory in the vagrant project
# (https://developer.hashicorp.com/vagrant/docs/vagrantfile#lookup-path)
# We need to define a function to climb up the directory tree to find
# the helm chart values.yaml file the way Vagrant climbs to find the Vagrantfile
def FindHelmChartPath()
  current_dir = Pathname.new(Dir.pwd)
  puts "Starting search for values.yaml file in CWD: " + current_dir.to_s
  
  loop do
    chart_dir = current_dir.join('chart')
    values_file = chart_dir.join('values.yaml')
    
    return values_file.to_s if chart_dir.directory? && values_file.file?
    
    break if current_dir.root?
    current_dir = current_dir.parent
  end
  
  nil
end

# Define a function to modify the helm chart values.yaml file for Vagrant appropriate settings
def ModifyHelmChart(values_file_path)
  # Check if the file exists
  unless File.exist?(values_file_path)
    puts "Error: #{values_file_path} does not exist. Exiting"
    exit 1
  end
  
  puts "Modifying Helm Chart values.yaml file: #{values_file_path}"
  # Read the contents of the file into memory
  lines = File.readlines(values_file_path)
  
  # Find the line containing "use_vagrant_config:"
  target_line_index = lines.index { |line| line.strip.start_with?("use_vagrant_config:") }
  
  if target_line_index.nil?
    puts "WARNING: Helm Chart 'use_vagrant_config' directive missing in values.yaml file. Skipping modification."
  elsif (lines[target_line_index].strip.downcase.end_with?("true")) #is the value already true?
    puts "WARNING: Helm Chart 'use_vagrant_config' directive is already set to 'true'. Skipping modification"
  else
    # Update the line in memory
    lines[target_line_index] = "use_vagrant_config: true\n"
    
    # Write the updated contents back to a temp file
    File.open(values_file_path + ".Vagrant_Modified", 'w') do |file|
      file.puts(lines)
    end 

    # Move the original values.yaml to values.yaml.vfbackup
    puts "Saving backup of original Helm Chart values.yaml file as: #{values_file_path}.vfbackup"
    File.rename(values_file_path, values_file_path + ".vfbackup")

    # Move the temp file to values.yaml
    File.rename(values_file_path + ".Vagrant_Modified", values_file_path)

    puts "Helm Chart values.yaml 'use_vagrant_config' directive now set to true."
  end
end

# Default behavior is to modify the helm chart values.yaml file for Vagrant appropriate settings
# (e.g. vagrant:vagrant as the default user and password, malcolm namespace, etc.)
# If you need to disable this behavior set an environment variable MODIFY_HELM_CHART=False when running vagrant up
# (e.g. run "MODIFY_HELM_CHART=False vagrant up")
helm_env_var = (ENV["MODIFY_HELM_CHART"].nil? ? "unset" : ENV["MODIFY_HELM_CHART"]).downcase # convert nil to "unset" to avoid .downcase on nil error
if (ARGV[0] == "up" && helm_env_var != "false" && helm_env_var != "no" && helm_env_var != "n")
  puts "Attempting to modify Helm chart values.yaml for Vagrant configuration"
  values_file_path = FindHelmChartPath() # traverse up the tree looking for chart/values.yaml
  if values_file_path
    puts "Found Helm Chart values.yaml file at: " + values_file_path
    ModifyHelmChart(values_file_path)
  else  
    puts "WARNING: Unable to locate Helm chart values.yaml file. Skipping Vagrant configuration modifications."
  end
else
  if ARGV[0] == "up"
    puts "Skipping Helm chart modify due to MODIFY_HELM_CHART environment variable directive"
  end
end


###### Begin Vagrant configure section ######
Vagrant.require_version ">= 2.3.7"
Vagrant.configure("2") do |config|
  script_choice = ENV['VAGRANT_SETUP_CHOICE'] || 'none'
  config.vm.box = "ubuntu/jammy64"
  config.disksize.size = '500GB'

  # NIC 1: Static IP with port forwarding
  if script_choice == 'use_istio'
    config.vm.network "forwarded_port", guest: 443, host: 8443, guest_ip: "10.0.2.100"
    # config.vm.network "forwarded_port", guest: 8080, host: 8080, guest_ip: "10.0.2.100"
  else
    config.vm.network "forwarded_port", guest: 80, host: 8080
  end

  # NIC 2: Promiscuous mode
  config.vm.network "private_network", type: "dhcp", virtualbox__intnet: "promiscuous", auto_config: false

  config.vm.provider "virtualbox" do |vb|
    vb.gui = true
    # Customize the amount of memory on the VM:
    vb.name = "Malcolm-Helm"
    # VCM vb.memory = "16192"
    vb.memory = "32768"
    vb.cpus = 8
  end

  config.vm.provision "shell", inline: <<-SHELL
    apt-get update
    apt-get upgrade -y

    # Turn off password authentication to make it easier to login
    sudo sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config

    # Configure promisc iface
    cp /vagrant/vagrant_dependencies/set-promisc.service /etc/systemd/system/set-promisc.service
    systemctl enable set-promisc.service

    # Setup RKE2
    curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION=v1.28.2+rke2r1 sh -
    mkdir -p /etc/rancher/rke2
    echo "cni: calico" > /etc/rancher/rke2/config.yaml

    systemctl start rke2-server.service
    systemctl enable rke2-server.service

    mkdir /root/.kube
    mkdir /home/vagrant/.kube

    cp /etc/rancher/rke2/rke2.yaml /home/vagrant/.kube/config
    cp /etc/rancher/rke2/rke2.yaml /root/.kube/config
    chmod 0600 /home/vagrant/.kube/config
    chmod 0600 /root/.kube/config
    chown -R vagrant:vagrant /home/vagrant/.kube

    ln -s /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
    snap install helm --classic
    node_name=$(kubectl get nodes -o jsonpath="{.items[0].metadata.name}")
    kubectl label nodes $node_name cnaps.io/node-type=Tier-1
    kubectl label nodes $node_name cnaps.io/suricata-capture=true
    kubectl label nodes $node_name cnaps.io/zeek-capture=true
    kubectl label nodes $node_name cnaps.io/arkime-capture=true

    kubectl apply -f /vagrant/vagrant_dependencies/sc.yaml

    grep -qxF 'alias k="kubectl"' /home/vagrant/.bashrc || echo 'alias k="kubectl"' >> /home/vagrant/.bashrc

    # Load specific settings sysctl settings needed for opensearch
    grep -qxF 'fs.inotify.max_user_instances=8192' /etc/sysctl.conf || echo 'fs.inotify.max_user_instances=8192' >> /etc/sysctl.conf
    grep -qxF 'fs.file-max=1000000' /etc/sysctl.conf || echo 'fs.file-max=1000000' >> /etc/sysctl.conf
    grep -qxF 'vm.max_map_count=1524288' /etc/sysctl.conf || echo 'vm.max_map_count=1524288' >> /etc/sysctl.conf
    sysctl -p

    # Add kernel modules needed for istio
    grep -qxF 'xt_REDIRECT' /etc/modules || echo 'xt_REDIRECT' >> /etc/modules
    grep -qxF 'xt_connmark' /etc/modules || echo 'xt_connmark' >> /etc/modules
    grep -qxF 'xt_mark' /etc/modules || echo 'xt_mark' >> /etc/modules
    grep -qxF 'xt_owner' /etc/modules || echo 'xt_owner' >> /etc/modules
    grep -qxF 'iptable_mangle' /etc/modules || echo 'iptable_mangle' >> /etc/modules

    # Update coredns so that hostname will resolve to their perspective IPs by enabling the host plugin
    myip_string=$(hostname -I)
    read -ra my_hostips <<< $myip_string
    cp /vagrant/vagrant_dependencies/Corefile.yaml /tmp/Corefile.yaml
    sed -i "s/###NODE_IP_ADDRESS###/${my_hostips[0]}/g" /tmp/Corefile.yaml
    kubectl replace -f /tmp/Corefile.yaml
    sleep 5
    echo "Rebooting the VM"

  SHELL

  config.vm.provision "reload"

  if script_choice == 'use_istio'
    config.vm.provision "shell", inline: <<-SHELL
      # Setup metallb
      helm repo add metallb https://metallb.github.io/metallb
      helm repo update metallb
      helm install metallb metallb/metallb -n metallb-system --create-namespace
      echo "Sleep for two minutes for cluster to come back up"
      sleep 120
      kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=900s --namespace metallb-system
      kubectl apply -f /vagrant/vagrant_dependencies/ipaddress-pool.yml
      kubectl apply -f /vagrant/vagrant_dependencies/l2advertisement.yaml

      # Delete rke ingress controller so it does not conflict with istio service mesh
      kubectl delete daemonset rke2-ingress-nginx-controller -n kube-system

      # Install istio service mesh
      helm repo add istio https://istio-release.storage.googleapis.com/charts
      helm repo update istio

      helm install istio istio/base --version 1.18.2 -n istio-system --create-namespace
      helm install istiod istio/istiod --version 1.18.2 -n istio-system --wait
      helm install tenant-ingressgateway istio/gateway --version 1.18.2 -n istio-system
      kubectl apply -f /vagrant/vagrant_dependencies/tenant-gateway.yaml

      # Create the certs
      mkdir certs

      # TODO this is not the right way to generate the certs I need to go back and fix this later.
      openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 -subj '/O=bigbang Inc./CN=bigbang.vp.dev' -keyout certs/ca.key -out certs/ca.crt
      openssl req -out certs/bigbang.vp.dev.csr -newkey rsa:2048 -nodes -keyout certs/bigbang.vp.dev.key -config /vagrant/vagrant_dependencies/req.conf -extensions 'v3_req'
      openssl x509 -req -sha256 -days 365 -CA certs/ca.crt -CAkey certs/ca.key -set_serial 0 -in certs/bigbang.vp.dev.csr -out certs/bigbang.vp.dev.crt

      cat certs/bigbang.vp.dev.crt > certs/chain.crt
      cat certs/ca.crt >> certs/chain.crt

      # openssl req -x509 -nodes -days 3650 -newkey rsa:2048 -keyout certs/istio.key -out certs/istio.crt -config /vagrant/vagrant_dependencies/req.conf -extensions 'v3_req'
      # Setup istio gateway with certs
      # kubectl create -n istio-system secret tls tenant-cert --key=certs/istio.key --cert=certs/istio.crt
      kubectl create -n istio-system secret tls tenant-cert --key=certs/bigbang.vp.dev.key --cert=certs/chain.crt

      # Install Malcolm enabling istio
      helm install malcolm /vagrant/chart -n malcolm --create-namespace --set istio.enabled=true --set ingress.enabled=false --set pcap_capture_env.pcap_iface=enp0s8
      # kubectl apply -f /vagrant/vagrant_dependencies/test-gateway.yml
      grep -qxF '10.0.2.100 malcolm.vp.bigbang.dev malcolm.test.dev' /etc/hosts || echo '10.0.2.100 malcolm.vp.bigbang.dev malcolm.test.dev' >> /etc/hosts
      echo "You may now ssh to your kubernetes cluster using ssh -p 2222 vagrant@localhost"
      hostname -I
    SHELL
  else
    config.vm.provision "shell", inline: <<-SHELL
      echo "Sleep for two minutes for cluster to come back up"
      sleep 120
      helm install malcolm /vagrant/chart -n malcolm --create-namespace --set istio.enabled=false --set ingress.enabled=true --set pcap_capture_env.pcap_iface=enp0s8
      echo "You may now ssh to your kubernetes cluster using ssh -p 2222 vagrant@localhost"
      hostname -I
    SHELL
  end
end

# Only attempt to restore the original Helm Chart values.yaml from backup
# if running 'vagrant up' and the environment variable isn't set to false, no, n
# Naote: this code runs before vagrant starts provisioning the VM despite being below Vagrant.configure()
if (ARGV[0] == "up" && helm_env_var != "false" && helm_env_var != "no" && helm_env_var != "n")
  # Clean up temporary values.yaml file changes if any occurred.
  puts "Checking for values.yaml.vfbackup"
  # Traverse up the tree looking for chart/values.yaml again 
  # just in case anything changed during vagrant up.
  values_file_path = FindHelmChartPath() 
  if values_file_path
    if File.exist?(values_file_path + ".vfbackup")
      puts "values.yaml.vfbackup file exists. Restoring original backup."
      
      # delete the recently modified values.yaml file
      File.delete(values_file_path)

      # rename the vfbackup file back to values.yaml
      File.rename(values_file_path + ".vfbackup", values_file_path)
    else
      puts "No .vfbackup file found. Skipping original file restore."
    end
  else 
    puts "WARNING: Unable to locate Helm chart values.yaml file. Skipping Helm Chart original file restore."
  end
else
  if ARGV[0] == "up" 
    puts "Skipping Helm chart restore due to MODIFY_HELM_CHART environment variable directive"
  end
end

