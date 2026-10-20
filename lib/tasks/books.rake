require "json"

namespace :books do
  desc "Scrape Books to Scrape into MongoDB (optional MAX_PAGES=2)"
  task scrape: :environment do
    settings = Scraping::Settings.load("books_to_scrape")
    logger = ActiveSupport::BroadcastLogger.new(Rails.logger, Logger.new($stdout))
    begin
      client = BooksToScrape::HttpClient.new(settings: settings, logger: logger)
      result = BooksToScrape::Crawler.new(client: client, logger: logger).call(max_pages: settings.max_pages)
      puts JSON.pretty_generate(result)
      abort "Scrape finished with failures; successful books were saved. See log/#{Rails.env}.log." if result[:failures].any?
    rescue Mongo::Error => e
      logger.error("scrape database error=#{e.class}: #{e.message}")
      abort "MongoDB unavailable. Run bin/mongo-start, then retry."
    end
  end
end
