require "test_helper"
require "stringio"

class BooksToScrapeHttpClientTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body)

  setup do
    @time = 0.0
    @calls = []
    @logs = StringIO.new
    @sleeps = []
  end

  def client_for(responses)
    BooksToScrape::HttpClient.new(
      logger: Logger.new(@logs), clock: -> { @time },
      sleeper: ->(seconds) { @sleeps << seconds; @time += seconds },
      transport: ->(uri) do
        @calls << [uri.to_s, @time]
        @time += 0.2
        response = responses.shift
        raise response if response.is_a?(Exception)
        response
      end
    )
  end

  test "network retries and successive requests all wait at least one second after completion" do
    client = client_for([Timeout::Error.new("offline"), Response.new("503", "busy"),
                         Response.new("200", "ok"), Response.new("200", "next")])
    assert_equal "ok", client.get(BooksToScrape::Url::BASE)
    assert_equal "next", client.get(BooksToScrape::Url::BASE)
    assert_equal 4, @calls.length
    assert @sleeps.all? { |seconds| seconds >= 0.999 }
    @calls.each_cons(2) { |first, second| assert_operator second[1] - first[1], :>=, 1.199 }
    assert_includes @logs.string, "attempt=1/3"
    assert_includes @logs.string, "status=503"
  end

  test "exhausted retries raise a typed network error and log the failure" do
    client = client_for(Array.new(3) { SocketError.new("offline") })
    error = assert_raises(Scraping::NetworkError) { client.get(BooksToScrape::Url::BASE) }
    assert_equal 3, error.attempts
    assert_equal 3, @calls.length
    assert_includes @logs.string, "fetch exhausted"
  end

  test "404 and redirects are not followed or retried" do
    ["404", "302"].each do |status|
      client = client_for([Response.new(status, "skip")])
      error = assert_raises(Scraping::NetworkError) { client.get(BooksToScrape::Url::BASE) }
      assert_equal 1, error.attempts
    end
    assert_equal 2, @calls.length
  end

  test "unsafe URLs and intervals are rejected before transport" do
    client = client_for([])
    ["https://example.com/", "http://books.toscrape.com/", "https://books.toscrape.com:8443/", "https://user@books.toscrape.com/"].each do |url|
      assert_raises(ArgumentError) { client.get(url) }
    end
    assert_empty @calls
    assert_raises(ArgumentError) { BooksToScrape::HttpClient.new(interval: 0.5) }
  end
end
