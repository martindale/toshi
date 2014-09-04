#!/usr/bin/env ruby
require_relative '../config/environment'

# run an instance
Toshi::PeerManager.new(Toshi.settings[:peers]).run
