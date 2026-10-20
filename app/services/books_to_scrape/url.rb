require "uri"

module BooksToScrape
  module Url
    BASE = "https://books.toscrape.com/".freeze

    def self.normalize(value, base: BASE)
      uri = URI.join(base, value)
      unless uri.is_a?(URI::HTTPS) && uri.host == "books.toscrape.com" && uri.port == 443 && !uri.userinfo
        raise ArgumentError, "Only https://books.toscrape.com/ is allowed"
      end
      uri.fragment = nil
      uri.query = nil
      uri.to_s
    end
  end
end
