Vagrant.configure("2") do |config|
  config.vm.synced_folder ".", "/vagrant", type: "virtualbox"
  config.vm.box = "debian/jessie64"
  config.vm.provider "virtualbox" do |v|
    v.memory = 1024
    v.customize [ "guestproperty", "set", :id, "/VirtualBox/GuestAdd/VBoxService/--timesync-set-threshold", 1000 ]
  end
  config.vm.network "forwarded_port", guest: 8500, host: 18500  # consul
  config.vm.network "forwarded_port", guest: 8200, host: 18200  # vault
  config.vm.network "forwarded_port", guest: 8202, host: 18202  # second vault
  config.vm.network "forwarded_port", guest: 9090, host: 19090  # prometheus
  config.vm.network "forwarded_port", guest: 3000, host: 3000   # grafana
  config.vm.provision "base",  type: "shell", path: "provision-base"
  config.vm.provision "consul",  type: "shell", path: "provision-consul"
  config.vm.provision "vault",   type: "shell", path: "provision-vault"
  config.vm.provision "prometheus",  run: "never", type: "shell", path: "provision-prometheus"
  config.vm.provision "node_exporter",  run: "never", type: "shell", path: "provision-node_exporter"
  config.vm.provision :docker
end
