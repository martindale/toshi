#!/usr/bin/env ruby

require_relative '../config/environment'

max_blocks = ARGV[0].to_s.to_i
restart = ARGV.include?('restart')
checkpoints_enabled = ARGV.include?('checkpoints')

file = ENV['BOOTSTRAP_FILE'] || "#{Toshi.root}/bootstrap.dat"
bootstrap = Toshi::Bootstrap.new(file)
bootstrap.start_from_scratch = restart
bootstrap.checkpoints_enabled = checkpoints_enabled
bootstrap.max_blocks = max_blocks if max_blocks > 0
bootstrap.run
