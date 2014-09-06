VAGRANTFILE_API_VERSION = "2"
COREOS_UPDATE_CHANNEL = "alpha"
VB_MEMORY = 1024
VB_CPUS = 1

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|

  config.vm.box = "coreos-%s" % COREOS_UPDATE_CHANNEL
  config.vm.box_version = ">= 308.0.1"
  config.vm.box_url = "http://%s.release.core-os.net/amd64-usr/current/coreos_production_vagrant.json" % COREOS_UPDATE_CHANNEL

  # plugin conflict
  if Vagrant.has_plugin?("vagrant-vbguest")
    config.vbguest.auto_update = false
  end

  config.vm.network "forwarded_port", guest: 5432, host: 21001 # postgres
  config.vm.network "forwarded_port", guest: 6379, host: 21002 # redis

  config.vm.provision "docker" do |d|
    d.run "redis",  image: "redis:2.8.9", args: "-p 6379:6379", daemonize: true
    d.run "postgres",  image: "postgres:9.3.5", args: "-p 5432:5432", daemonize: true
  end

  config.vm.provider "virtualbox" do |v|
    v.memory = VB_MEMORY
    v.cpus = VB_CPUS

    # On VirtualBox, we don't have guest additions or a functional vboxsf
    # in CoreOS, so tell Vagrant that so it can be smarter.
    v.check_guest_additions = false
    v.functional_vboxsf     = false
  end

end
