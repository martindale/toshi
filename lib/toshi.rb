require 'bitcoin'
require 'erb'
require 'logger'
require 'yaml'
require 'toshi/version'

module Toshi
  # core.h: CTransaction::CURRENT_VERSION
  CURRENT_TX_VERSION = 1

  # main.h
  MAX_STANDARD_TX_SIZE = 100000

  # satoshis per kb, main.cpp: CFeeRate CTransaction::minRelayTxFee = CFeeRate(1000);
  MIN_RELAY_TX_FEE = 1000

  autoload :BlockHeaderIndex,   'toshi/block_header_index'
  autoload :BlockchainStorage,  'toshi/blockchain_storage'
  autoload :Bootstrap,          'toshi/bootstrap'
  autoload :ConnectionHandler,  'toshi/connection_handler'
  autoload :PeerManager,        'toshi/peer_manager'
  autoload :Logging,            'toshi/logging'
  autoload :MemoryPool,         'toshi/memory_pool'
  autoload :OutputsCache,       'toshi/outputs_cache'
  autoload :Processor,          'toshi/processor'
  autoload :Api,                'toshi/api'

  module Models
    autoload :Address,                    'toshi/models/address'
    autoload :AddressSettings,            'toshi/models/address_settings'
    autoload :Block,                      'toshi/models/block'
    autoload :Input,                      'toshi/models/input'
    autoload :Output,                     'toshi/models/output'
    autoload :Peer,                       'toshi/models/peer'
    autoload :RawBlock,                   'toshi/models/raw_block'
    autoload :RawTransaction,             'toshi/models/raw_transaction'
    autoload :Transaction,                'toshi/models/transaction'
    autoload :UnconfirmedAddress,         'toshi/models/unconfirmed_address'
    autoload :UnconfirmedInput,           'toshi/models/unconfirmed_input'
    autoload :UnconfirmedOutput,          'toshi/models/unconfirmed_output'
    autoload :UnconfirmedRawTransaction,  'toshi/models/unconfirmed_raw_transaction'
    autoload :UnconfirmedTransaction,     'toshi/models/unconfirmed_transaction'
  end

  def self.env
    @env ||= (ENV['TOSHI_ENV'] || ENV['RACK_ENV'] || 'development').to_sym
  end

  def self.root
    @root ||= File.expand_path('../..', __FILE__)
  end

  def self.settings
    @settings ||= begin
      config_file = [
        "#{root}/config/toshi.yml",
        "#{root}/config/toshi.yml.example"
      ].find { |f| File.exists?(f) }

      settings = {}
      YAML.load(ERB.new(File.read(config_file)).result)[env.to_s].each do |key, value|
        settings[key.to_sym] = value
      end

      # default settings
      settings[:network] ||= 'testnet3'
      settings[:max_peers] ||= 8
      settings[:log_level] ||= 'info'
      settings[:debug] = true # TODO: remove once logging is cleaned up

      # convert redis setting to hash
      if settings[:redis].nil?
        settings[:redis] = {}
      elsif settings[:redis].is_a?(String)
        settings[:redis] = { url: settings[:redis] }
      end

      # additional postgres options
      settings[:database_opts] = { adapter: 'postgres' }

      # automatic docker support
      if ENV['REDIS_PORT_6379_TCP_ADDR']
        settings[:redis][:host] = ENV['REDIS_PORT_6379_TCP_ADDR']
        settings[:redis][:port] = ENV['REDIS_PORT_6379_TCP_PORT']
      end
      if ENV['POSTGRES_PORT_5432_TCP_ADDR']
        settings[:database_opts][:host] = ENV['POSTGRES_PORT_5432_TCP_ADDR']
        settings[:database_opts][:port] = ENV['POSTGRES_PORT_5432_TCP_PORT']
        settings[:database_opts][:user] = 'postgres'
      end

      # initialize bitcoin-ruby with correct network
      Bitcoin.network = settings[:network]

      settings
    end
  end

  def self.logger
    @logger ||= begin
      logger = Logger.new(STDOUT)

      # set log level
      level = settings[:log_level].to_s.upcase
      logger.level = Logger.const_get(level).to_i rescue 1

      # slightly nicer default format
      logger.formatter = proc do |severity, time, progname, msg|
        "#{time.utc.iso8601(3)} #{::Process.pid} #{progname} #{severity}: #{msg}\n"
      end

      logger
    end
  end

  def self.logger=(logger)
    @logger = logger
  end
end

require "toshi/db"
require "toshi/mq"
require "toshi/utils"
require "toshi/workers/block_worker"
require "toshi/workers/transaction_worker"
