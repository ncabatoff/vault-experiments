Vagrant.configure("2") do |config|
  config.vm.synced_folder ".", "/vagrant", type: "sshfs"
  config.vm.box = "debian/jessie64"
  config.vm.provider "virtualbox" do |v|
    v.memory = 1024
  end
  config.vm.provision "base",  type: "shell", path: "provision-base"
  config.vm.provision "consul",  type: "shell", path: "provision-consul"
  config.vm.provision "vault",   type: "shell", path: "provision-vault"
end
