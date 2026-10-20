require "test_helper"
require "stringio"

class ScrapingPipelineTest < ActiveSupport::TestCase
  include BookTestData
  class FixtureFetcher
    def initialize(pages)
      @pages = pages
    end
    def get(url)
      @pages.fetch(url) { raise Scraping::NetworkError.new("Timed out after retries", url: url, attempts: 3) }
    end
  end

  setup do
    Book.delete_all
    ScrapeRun.delete_all
    @base = BooksToScrape::Url::BASE
    @url = "#{@base}catalogue/a-light-in-the-attic_1000/index.html"
    @html = file_fixture("book.html").read
    @settings = Scraping::Settings.load("books_to_scrape", env: {})
    @logger = Logger.new(StringIO.new)
  end

  def catalogue(urls)
    urls.map { |url| %(<article class="product_pod"><h3><a href="#{url}">book</a></h3></article>) }.join
  end

  def crawler_for(pages, **options)
    BooksToScrape::Crawler.new(settings: @settings, client: FixtureFetcher.new(pages), logger: @logger, **options)
  end

  def legacy_book
    raw = attributes_for_book(url: @url).except(:source, :upc, :stock_quantity)
    Book.collection.insert_one(raw).inserted_id
  end

  test "catalogue redesign errors without writing and records classified reasons" do
    legacy_book
    before = Book.collection.find.to_a
    result = crawler_for({ @base => "<html>new layout</html>" }).call
    assert_equal 0, result[:books_saved]
    assert_equal 1, result[:batches_rejected]
    assert_equal 1, result[:failure_counts]["parse"]
    assert_equal before, Book.collection.find.to_a
    run = ScrapeRun.find(result[:run_id])
    assert_equal "failed", run.status
    assert run.started_at
    assert run.finished_at
    assert_equal "parse", run.failures.first.fetch("kind")
  end

  test "one redesigned detail rejects the whole batch before any valid writes" do
    legacy_book
    second = "#{@base}catalogue/redesigned/index.html"
    before = Book.collection.find.to_a
    result = crawler_for({ @base => catalogue([@url, second]), @url => @html, second => "<html>new structure</html>" }).call
    assert_equal 0, result[:books_saved]
    assert_equal 1, result[:batches_rejected]
    assert_equal 1, result[:failure_counts]["parse"]
    assert_equal before, Book.collection.find.to_a
  end

  test "missing price refuses writes and leaves every legacy field untouched" do
    legacy_book
    before = Book.collection.find.to_a
    missing = @html.sub(/<p class="price_color">.*?<\/p>/m, "")
    result = crawler_for({ @base => catalogue([@url]), @url => missing }).call
    assert_equal 0, result[:books_saved]
    assert_equal 1, result[:batches_rejected]
    assert result[:failures].any? { |failure| failure[:kind] == "validation" && failure[:fields]&.include?(:price) }
    assert_equal before, Book.collection.find.to_a
  end

  test "missing critical fields at threshold reject all good and bad records" do
    legacy_book
    before = Book.collection.find.to_a
    urls = (1..4).map { |index| "#{@base}catalogue/batch-#{index}/index.html" }
    pages = { @base => catalogue(urls) }
    urls.each_with_index { |url, index| pages[url] = @html.sub("a897fe39b1053632", "fixture-upc-#{index}") }
    pages[urls.last] = pages[urls.last].sub("star-rating Three", "star-rating Unknown")
    result = crawler_for(pages).call
    assert_equal 0, result[:books_saved]
    assert_equal 1, result[:batches_rejected]
    assert result[:failures].any? { |failure| failure[:scope] == "batch" && failure[:reason].include?("1/4") }
    assert_equal before, Book.collection.find.to_a
  end

  test "below threshold only the invalid book is refused and page size is advisory" do
    urls = (1..5).map { |index| "#{@base}catalogue/batch-#{index}/index.html" }
    pages = { @base => catalogue(urls) }
    urls.each_with_index { |url, index| pages[url] = @html.sub("a897fe39b1053632", "fixture-upc-#{index}") }
    pages[urls.last] = pages[urls.last].sub("<th>UPC</th>", "<th>Other</th>")
    result = crawler_for(pages).call
    assert_equal 4, result[:books_saved]
    assert_equal 4, Book.count
    assert_equal 0, result[:batches_rejected]
    assert_equal 1, result[:failure_counts]["validation"]
    assert result[:warnings].any? { |warning| warning[:reason].include?("advisory") }
  end

  test "two crawls upsert UPC and promote a legacy document without duplication" do
    id = legacy_book
    crawler = crawler_for({ @base => catalogue([@url]), @url => @html })
    first = crawler.call
    second = crawler.call
    assert_equal 1, Book.count
    assert_equal id, Book.first.id
    assert_equal "a897fe39b1053632", Book.first.upc
    assert_equal "books_to_scrape", Book.first.source
    assert_equal 22, Book.first.stock_quantity
    assert_equal 1, first[:books_saved]
    assert_equal 1, second[:books_saved]
    assert_equal 2, ScrapeRun.count
    assert ScrapeRun.all.all? { |run| run.status == "completed" && run.finished_at && run.books_saved == 1 }
  end

  test "one exhausted network failure is counted with attempts while another book saves" do
    missing = "#{@base}catalogue/missing/index.html"
    result = crawler_for({ @base => catalogue([missing, @url]), @url => @html }).call
    assert_equal 1, result[:books_saved]
    assert_equal 1, result[:failure_counts]["network"]
    assert_equal 0, result[:failure_counts]["parse"]
    run = ScrapeRun.find(result[:run_id])
    assert_equal "completed_with_errors", run.status
    assert_equal 3, run.failures.first.fetch("attempts")
    assert_equal 1, run.failure_counts["network"]
  end

  test "zero books from a parser are rejected without modifying stored books" do
    legacy_book
    before = Book.collection.find.to_a
    empty_parser = Object.new
    def empty_parser.catalogue(_html, url:)
      { book_urls: [], next_url: nil }
    end
    result = crawler_for({ @base => "fixture" }, parser: empty_parser).call
    assert_equal 1, result[:batches_rejected]
    assert_equal 0, result[:books_saved]
    assert_equal before, Book.collection.find.to_a
  end

  test "an interrupted fetch never records a successful scrape run" do
    interrupted = Object.new
    def interrupted.get(_url)
      raise Interrupt, "cancelled"
    end
    crawler = BooksToScrape::Crawler.new(settings: @settings, client: interrupted, logger: @logger)
    assert_raises(Interrupt) { crawler.call }
    assert_equal 1, ScrapeRun.count
    assert_equal "failed", ScrapeRun.first.status
    assert ScrapeRun.first.finished_at
    assert_equal 0, Book.count
  end
end
