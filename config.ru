STDOUT.sync = STDERR.sync = true

require_relative 'config/environment'

require "toshi/web/www"
require "toshi/web/api"
require "toshi/web/websocket"
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
