require 'securerandom'
require 'json'

module RedisMQ

  def self.redis(&blk)
    Sidekiq.redis(&blk)
  end

  def self.redis_destroy(key, id)
    redis{|conn|
      conn.srem(key, id)
      conn.del("#{key}:#{id}:started")
      conn.del("#{key}:#{id}:ping")
      conn.del("#{key}:#{id}:config")
      conn.del("#{key}_queue:#{id}")
    }
  end

  def self.redis_create(key, id, config)
    time = Time.now.to_f.to_s
    redis{|conn|
      conn.sadd(key, id)
      conn.set("#{key}:#{id}:started", time)
      conn.set("#{key}:#{id}:ping", time)
      conn.set("#{key}:#{id}:config", config.to_json)
    }
  end

  def self.redis_get(key); redis{|conn| conn.get(key) }; end
  def self.redis_set(key, value); redis{|conn| conn.set(key, value) }; end

  def self.redis_pop_queues(sorted_sets=[], do_loop=false, poll_interval=2, &blk)
    now = Time.now.to_f.to_s
    begin
      redis{|conn|
        sorted_sets.each{|sorted_set|
          while message = conn.zrangebyscore(sorted_set, '-inf', now, :limit => [0, 1]).first do
            if conn.zrem(sorted_set, message)
              job = JSON.parse(message)
              blk.call(job)
            end
          end
        }
      }
    rescue => ex
      logger.error ex.message
      logger.error ex.backtrace.first
    end
    after(poll_interval) { poll(sorted_sets, poll_interval, do_loop) } if do_loop
  end

  def self.redis_push_queue(key, id, job)
    redis{|conn|
      conn.zadd(id ? "#{key}_queue:#{id}" : key, Time.now.to_f.to_s, JSON.generate(job))
    }
  end

  #def self.logger; Celluloid.logger; end
  def self.logger; Sidekiq.logger; end

  def self.redis_all(key); redis{|conn| conn.smembers(key) }; end
  def self.redis_count(key); redis{|conn| conn.scard(key) }; end

  class Channel
    attr_reader :key, :id, :last_ping
    def initialize(type=:worker, config={}, &blk)
      @config = config
      @id = @config['id'] || SecureRandom.urlsafe_base64(8)
      @key = case type
             when :worker; 'io_workers'
             when :client; 'io_clients'
             else @config['key']
             end
      @last_ping = 0
      @process_callback = blk
      RedisMQ.redis_create(@key, @id, @config)
    end

    def to_s
      @key + "-" + @id
    end

    def clear
      RedisMQ.redis_destroy(@key, @id)
    end

    def ping
      time = Time.now.to_f
      if @last_ping <= (time - PING_TIMEOUT); @last_ping = time
        RedisMQ.redis_set("#{@key}:#{@id}:ping", time.to_s)
      end
    end

    def poll(do_loop=false)
      ping
      sorted_sets = ["#{@key}_queue", "#{@key}_queue:#{@id}"]
      RedisMQ.redis_pop_queues(sorted_sets, do_loop){|job|
        @process_callback.call(self, job) if @process_callback
        @last_response = job
      }
    end

    def pkt(job)
      {"sender" => { 'id' => @id, "type" => @key }}.merge(job)
    end

    # push to specific worker
    def worker_push(id, job)
      return if id == @id
      key, job = 'io_workers', pkt(job)
      RedisMQ.redis_push_queue(key, id, job)
    end

    # push to specific Client
    def client_push(id, job)
      return if id == @id
      key, job = 'io_clients', pkt(job)
      RedisMQ.redis_push_queue(key, id, job)
    end

    # push to specific peer
    def self.peer_push(id, peer, job)
      job.merge!({ 'peer' => peer })
      RedisMQ.redis_push_queue('io_workers', id, job)
    end

    # push to random available worker
    def workers_push(job)
      key, job = 'io_workers', pkt(job)
      return if @key == key
      RedisMQ.redis_push_queue("#{key}_queue", nil, job)
    end

    # push to all workers
    def workers_push_all(job)
      key, job = 'io_workers', pkt(job)
      RedisMQ.redis_all(key).each{|id| next if id == @id
        RedisMQ.redis_push_queue(key, id, job)
      }
    end

    # push to all clients
    def clients_push_all(job)
      key, job = 'io_clients', pkt(job)
      RedisMQ.redis_all(key).each{|id| next if id == @id
        RedisMQ.redis_push_queue(key, id, job)
      }
    end

    def reply(pkt, job)
      case pkt['sender']['type']
      when 'io_workers';      worker_push(pkt['sender']['id'], job)
      when 'io_clients';      client_push(pkt['sender']['id'], job)
      end if pkt['sender']
    end

    # called from the sidekiq block processing worker
    def self.reply_to_peer(pkt, job)
      return false unless pkt['sender']
      # should only be sent to io_workers -- they manage peers.
      return false if pkt['sender']['type'] != 'io_workers'
      peer = pkt['sender']['peer']
      # not from a peer
      return false if peer.nil?
      peer_push(pkt['sender']['id'], peer, job)
      true
    end

    def self.workers_all; RedisMQ.redis_all("io_workers"); end
    def self.clients_all; RedisMQ.redis_all("io_clients"); end
    def self.workers_count; RedisMQ.redis_count("io_workers"); end
    def self.clients_count; RedisMQ.redis_count("io_clients"); end

    POLL_TIMEOUT = 0.5
    PING_TIMEOUT = 30
    FUSH_TIMEOUT = 120

    def self.flush!
      active, flushed, flush_time = 0, 0, Time.now.to_f - FUSH_TIMEOUT
      ['io_workers', 'io_clients'].each{|key|
        RedisMQ.redis_all(key).each{|id|
          if RedisMQ.redis_get("#{key}:#{id}:ping").to_f < flush_time
            flushed += 1
            RedisMQ.redis_destroy(key, id)
          else
            active += 1
          end
        }
      }
      [active, flushed]
    end

    #
    # blocking client methods
    #
    def init_poll
      EM.schedule{ EM.add_periodic_timer(POLL_TIMEOUT){ poll } }
    end

    def init_heartbeat
      EM.schedule{ EM.add_periodic_timer(PING_TIMEOUT){ ping } }
    end

    def workers_msg(msg)
      workers_push(msg)
      until @last_response
        poll; sleep 0.1
      end
      response = @last_response
      @last_response = nil
      response
    end
  end

  def self.redis_get(key); redis{|conn| conn.get(key) }; end
end
