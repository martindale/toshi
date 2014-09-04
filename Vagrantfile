# Vagrantfile API/syntax version. Don't touch unless you know what you're doing!
VAGRANTFILE_API_VERSION = "2"

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  # All Vagrant configuration is done here. The most common configuration
  # options are documented and commented below. For a complete reference,
  # please see the online documentation at vagrantup.com.

  config.vm.box = "ubuntu/trusty64"
  config.vm.network "forwarded_port", guest: 5432, host: 21001 # postgres
  config.vm.network "forwarded_port", guest: 6379, host: 21002 # redis
  config.vm.provision :shell, path: "config/vagrant/provision.sh"
  config.vm.synced_folder ".", "/vagrant"

  config.vm.provider "virtualbox" do |v|
    v.memory = 1024

    # uncomment if you need to access vbox gui
    # v.gui = true
  end
end
