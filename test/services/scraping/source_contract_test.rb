require "test_helper"
require "stringio"

# An in-memory adapter proves the shared pipeline has no BooksToScrape dependency.
# This is a test source, not an additional real scraping target.
class SourceContractTest < ActiveSupport::TestCase
  module FixtureSite
    BASE = "https://fixture-books.invalid/"
    URL = "#{BASE}book/fixture"
    module UrlPolicy
      def self.normalize(url)
        uri = URI.join(FixtureSite::BASE, url)
        raise ArgumentError, "Unexpected fixture host" unless uri.host == "fixture-books.invalid" && uri.scheme == "https"
        uri.to_s
      end
    end
    class Parser
      def catalogue(_html, url:)
        { book_urls: [URL], next_url: nil }
      end
      def book(_html, url:)
        { title: "Fixture Book", upc: "fixture-upc", price: "10.50", currency: "GBP",
          rating: "4", in_stock: true, stock_quantity: nil, category: "Fiction", url: url }
      end
    end
    class Fetcher
      def get(_url)
        "offline fixture"
      end
    end
  end

  test "an independent adapter uses the same normalizer persistence and v1 serializer" do
    Book.delete_all
    settings = Scraping::Settings.load("books_to_scrape", env: {})
    result = Scraping::Runner.new(
      source: "fixture_site", start_url: FixtureSite::BASE, settings: settings,
      fetcher: FixtureSite::Fetcher.new, parser: FixtureSite::Parser.new,
      normalizer: Scraping::Normalizer.new(source: "fixture_site", url_policy: FixtureSite::UrlPolicy),
      batch_validator: Scraping::BatchValidator.new(critical_rejection_ratio: settings.critical_rejection_ratio,
                                                   expected_page_size: settings.expected_page_size),
      logger: Logger.new(StringIO.new)
    ).call
    assert_equal 1, result[:books_saved]
    assert_empty result[:failures]
    book = Book.find_by(source: "fixture_site", upc: "fixture-upc")
    assert_equal 1050, book.price_cents
    assert_equal "fixture_site", Api::V1::BookSerializer.call(book)[:source]
    assert_nil book.stock_quantity
  end
end
