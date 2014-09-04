require 'eventmachine'
require 'sinatra'
require "sinatra/namespace"

module Toshi
  class Web < ::Sinatra::Base
    register Sinatra::Namespace
    class NotFoundError < StandardError; end
    class InvalidFormatError < StandardError; end

    set :root,            File.dirname(File.dirname(__FILE__))
    set :public_folder,   Proc.new { File.join(root, "toshi/web/static") }
    set :views,           Proc.new { File.join(root, "toshi/web/views") }

    get '/' do
      @available_peers = Toshi::Models::Peer.count
      @connected_peers = Toshi::Models::Peer.connected.count
      @available_clients = RedisMQ::Channel.clients_count
      @available_workers = RedisMQ::Channel.workers_count

      content_type 'text/html'
      erb :index
    end

    get '/websockets' do
      erb :websocket
    end
  end
end
