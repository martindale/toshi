require_relative 'application'
require 'bugsnag'

Bugsnag.configure do |config|
  config.api_key = ENV['BUGSNAG_API_KEY']
  config.endpoint = ENV['BUGSNAG_URL']
  config.notify_release_stages = ['production']
  config.project_root = Toshi.root.to_s
  config.release_stage = Toshi.env.to_s
  config.use_ssl = true
end

# sync stdout to make logging easier
STDOUT.sync = true unless Toshi.env == :production

# connect db
Toshi.connect

def error_handler ex, ctx_hash
  p ex
  ex.backtrace.each{|frame|
    p frame
  }
end

# connect sidekiq/redis
Sidekiq.configure_server{|config|
  config.redis = { url: Toshi.settings[:redis_url] }
  config.error_handlers << Proc.new {|ex,ctx_hash| error_handler(ex, ctx_hash) }
}

Sidekiq.configure_client{|config|
  config.redis = { url: Toshi.settings[:redis_url] }
  config.error_handlers << Proc.new {|ex,ctx_hash| error_handler(ex, ctx_hash) }
}

# run sidekiq synchronously in test environment
if Toshi.env == :test
  require 'sidekiq/testing'
  Sidekiq::Testing.inline!
end

# so transaction processors process unique jobs based only on the tx hash
SidekiqUniqueJobs::Config.unique_args_enabled = true
