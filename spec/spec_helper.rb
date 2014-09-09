ENV['RACK_ENV'] ||= 'test'
ENV['TOSHI_ENV'] ||= 'test'
ENV['TOSHI_NETWORK'] ||= 'testnet3'

require_relative '../config/environment'
require 'database_cleaner'
require "rack/test"

Dir["./spec/support/**/*.rb"].sort.each { |f| require f }

RSpec.configure do |config|
  config.filter_run_excluding :performance
  config.order = :random
  Kernel.srand config.seed

  config.include Requests::JsonHelpers, :type => :request
  config.include Rack::Test::Methods

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.syntax = :expect
    mocks.verify_partial_doubles = true
  end

  config.before :suite do
    DatabaseCleaner.clean_with :truncation
  end

  config.before do |config|
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.start
    Sidekiq.redis { |c| c.flushdb }
  end

  config.after do
    DatabaseCleaner.clean
  end
end
