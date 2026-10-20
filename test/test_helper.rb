ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "digest"

raise "Tests require the isolated test database" unless Rails.env.test? && Mongoid.default_client.database.name == "book_price_api_test"

# Parser and HTTP tests use fixtures/fakes; no test may fetch a real web page.
module NoExternalHttpInTests
  def request(*)
    raise "HTTP networking is disabled in tests; use a saved fixture or fake transport"
  end
end
require "net/http"
Net::HTTP.prepend(NoExternalHttpInTests)

Scraping::BookRepository.new.prepare!
Minitest.after_run do
  Book.delete_all
  ScrapeRun.delete_all
  Mongoid.disconnect_clients
end

module BookTestData
  def attributes_for_book(**overrides)
    url = overrides.fetch(:url, "https://books.toscrape.com/catalogue/test-book_1/index.html")
    {
      source: "books_to_scrape", upc: Digest::SHA256.hexdigest(url)[0, 16], stock_quantity: 22,
      title: "示例 Book", price_cents: 1999, currency: "GBP", rating: 5,
      in_stock: true, category: "Fantasy",
      url: url
    }.merge(overrides)
  end

  def save_book(**overrides)
    attributes = attributes_for_book(**overrides)
    Book.upsert_from_scrape!(attributes)
    Book.find_by(url: attributes[:url])
  end
end

module ActiveSupport
  class TestCase
    # Keep tests sequential to limit memory and avoid shared MongoDB cleanup races.

    # Add more helper methods to be used by all tests here...
  end
end
