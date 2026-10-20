require "test_helper"
require "stringio"

class BooksToScrapeCrawlerTest < ActiveSupport::TestCase
  class FakeClient
    attr_reader :calls
    def initialize(pages)
      @pages, @calls = pages, []
    end
    def get(url)
      @calls << url
      @pages.fetch(url) { raise Scraping::NetworkError.new("fixture fetch failed", url: url, attempts: 3) }
    end
  end

  class FakeRepository
    attr_reader :saved
    def initialize
      @saved = []
    end
    def prepare!; end
    def upsert_from_scrape!(attributes)
      @saved << attributes
    end
  end

  setup do
    @base = BooksToScrape::Url::BASE
    @book_url = "#{@base}catalogue/a-light-in-the-attic_1000/index.html"
    @page2 = "#{@base}catalogue/page-2.html"
    @html = file_fixture("book.html").read
    @repository = FakeRepository.new
    @logger = Logger.new(StringIO.new)
    ScrapeRun.delete_all
  end

  def catalogue(urls, next_url: nil)
    links = urls.map { |url| %(<article class="product_pod"><h3><a href="#{url}">book</a></h3></article>) }.join
    links + (next_url ? %(<li class="next"><a href="#{next_url}">next</a></li>) : "")
  end

  def crawl(pages, **options)
    @client = FakeClient.new(pages)
    BooksToScrape::Crawler.new(settings: Scraping::Settings.load("books_to_scrape", env: {}), client: @client, repository: @repository, logger: @logger).call(**options)
  end

  test "default follows all pages and skips duplicate book links" do
    result = crawl({ @base => catalogue([@book_url], next_url: @page2),
                     @page2 => catalogue([@book_url]), @book_url => @html })
    assert_equal 2, result[:pages_fetched]
    assert_equal 1, result[:books_saved]
    assert_equal false, result[:limited]
    assert_empty result[:failures]
    assert_equal 1, @client.calls.count(@book_url)
  end

  test "one failed book does not prevent saving the next book" do
    missing = "#{@base}catalogue/missing/index.html"
    result = crawl({ @base => catalogue([missing, @book_url]), @book_url => @html })
    assert_equal 1, result[:books_saved]
    assert_equal missing, result[:failures].first[:url]
  end

  test "page limit avoids fetching remaining pages" do
    result = crawl({ @base => catalogue([@book_url], next_url: @page2), @book_url => @html }, max_pages: 1)
    assert_equal 1, result[:pages_fetched]
    assert result[:limited]
    refute_includes @client.calls, @page2
  end

  test "missing catalogue returns partial failure without crashing" do
    result = crawl({ @base => catalogue([@book_url], next_url: @page2), @book_url => @html })
    assert_equal 1, result[:books_saved]
    assert_equal @page2, result[:failures].first[:url]
  end
end
