STDOUT.sync = STDERR.sync = true

require_relative 'config/environment'

require "toshi/web"
require "toshi/api"
require "toshi/websocket_server"
require 'sidekiq/web'

use Rack::CommonLogger
use Bugsnag::Rack

app = Rack::URLMap.new(
  '/'          => Toshi::Web,
  '/api'       => Toshi::Api,
  '/sidekiq'   => Sidekiq::Web,
)

websocket_middleware = Toshi::WebSocketMiddleware.new(app)

run websocket_middleware
