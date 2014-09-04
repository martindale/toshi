# spec/support/request_helpers.rb

module Requests
  module JsonHelpers
    def json
      @json ||= JSON.parse(last_response.body)
    end
  end
end