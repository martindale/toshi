module Toshi
  module Logging
    # A unique logger for the current class
    def logger
      @logger ||= begin
        logger = Toshi.logger.dup
        logger.progname = self.class.name
        logger
      end
    end
  end
end
