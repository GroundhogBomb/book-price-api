module BooksToScrape
  class HttpClient < Scraping::HttpFetcher
    def initialize(settings: Scraping::Settings.load("books_to_scrape"), interval: nil, max_attempts: nil, **options)
      overrides = { interval: interval, max_attempts: max_attempts }.compact
      super(settings: settings.with(**overrides), url_policy: Url, **options)
    end
  end
end
