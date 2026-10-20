module BooksToScrape
  class Crawler < Scraping::Runner
    SOURCE = "books_to_scrape".freeze

    def initialize(settings: Scraping::Settings.load(SOURCE), client: nil, parser: Parser.new,
                   repository: Scraping::BookRepository.new, recorder: Scraping::RunRecorder.new, logger: Rails.logger)
      super(
        source: SOURCE, start_url: Url::BASE, settings: settings,
        fetcher: client || HttpClient.new(settings: settings, logger: logger), parser: parser,
        normalizer: Scraping::Normalizer.new(source: SOURCE, url_policy: Url),
        batch_validator: Scraping::BatchValidator.new(critical_rejection_ratio: settings.critical_rejection_ratio,
                                                     expected_page_size: settings.expected_page_size),
        repository: repository, recorder: recorder, logger: logger
      )
    end
  end
end
