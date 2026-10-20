module Scraping
  class ValidationError < StandardError
    attr_reader :fields
    def initialize(message, fields: [])
      super(message)
      @fields = fields.freeze
    end
  end
end
