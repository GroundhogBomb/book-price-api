module Scraping
  class NetworkError < StandardError
    attr_reader :url, :attempts
    def initialize(message, url:, attempts:)
      super(message)
      @url, @attempts = url, attempts
    end
  end
end
