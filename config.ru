STDOUT.sync = STDERR.sync = true

require_relative 'config/environment'

require "toshi/web/www"
require "toshi/web/api"
require "toshi/web/websocket"
require 'sidekiq/web'

use Rack::CommonLogger
use Bugsnag::Rack

app = Rack::URLMap.new(
  '/'          => Toshi::Web::WWW,
  '/api/v0'    => Toshi::Web::Api,
  '/sidekiq'   => Sidekiq::Web,
)

app = Toshi::Web::WebSockets.new(app)

run app
