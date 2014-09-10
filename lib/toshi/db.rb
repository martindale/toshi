require 'pg'
require 'sequel'

module Toshi
  class << self
    attr_accessor :db

    def connect
      self.db = Sequel.connect(settings[:database], settings[:database_opts])
    end
  end
end
