require 'resolv'

module Toshi
  module Models
    class Peer < Sequel::Model

      def self.disconnected
        filter(connected: false)
      end

      def self.connected
        filter(connected: true)
      end

      def self.bootstrap(dns=nil)
        seed = dns || Bitcoin.network[:dns_seeds].sample
        if seed
          return Resolv::DNS.new.getresources(seed, Resolv::DNS::Resource::IN::A).collect{|r| r.address.to_s}.collect{|ip|
            p = Peer.find_or_create(ip: ip, port: Bitcoin.network[:default_port], services: 1)
            p.last_seen = Time.now
            p.save
          }
        end
        return nil
      end

      attr_reader :connection

      def self.get(ip)
        peer = Peer.where(ip: ip).first
        peer = Peer.find_or_create(ip: ip, port: Bitcoin.network[:default_port], services: 1, last_seen: Time.now, connected: false) if !peer
        return nil if peer.connected
        peer
      end

      def connect!(io_worker)
        return nil if connected
        @connection = EM.connect(ip, port, Toshi::ConnectionHandler, nil, ip, port, :out, self, io_worker)
      end
    end
  end
end
