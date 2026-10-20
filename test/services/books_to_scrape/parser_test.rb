require "test_helper"

class BooksToScrapeParserTest < ActiveSupport::TestCase
  setup do
    @parser = BooksToScrape::Parser.new
    @catalogue = file_fixture("catalogue.html").read
    @book = file_fixture("book.html").read
    @url = "https://books.toscrape.com/catalogue/a-light-in-the-attic_1000/index.html"
  end

  test "catalogue resolves detail URLs and next page from saved HTML" do
    page = @parser.catalogue(@catalogue, url: BooksToScrape::Url::BASE)
    assert_equal 20, page[:book_urls].length
    assert_equal @url, page[:book_urls].first
    assert_equal "https://books.toscrape.com/catalogue/page-2.html", page[:next_url]
  end

  test "relative pagination and last page are parsed independently of page size" do
    html = @catalogue.sub('href="catalogue/page-2.html"', 'href="page-3.html"')
    page = @parser.catalogue(html, url: "https://books.toscrape.com/catalogue/page-2.html")
    assert_equal "https://books.toscrape.com/catalogue/page-3.html", page[:next_url]
    last_page = @catalogue.sub(/<li class="next">.*?<\/li>/m, "")
    assert_nil @parser.catalogue(last_page, url: BooksToScrape::Url::BASE)[:next_url]
  end

  test "detail yields raw canonical fields including UPC and quantity" do
    raw = @parser.book(@book, url: @url)
    assert_equal({ title: "A Light in the Attic", price: "51.77", currency: "GBP",
                   rating: "3", in_stock: true, url: @url, category: "Poetry",
                   upc: "a897fe39b1053632", stock_quantity: "22" }, raw)
  end

  test "out of stock and Unicode titles parse without network" do
    html = @book.sub("In stock (22 available)", "Out of stock (0 available)")
                .sub("<h1>A Light in the Attic</h1>", "<h1>中文 &amp; Café</h1>")
    raw = @parser.book(html, url: @url)
    assert_equal false, raw[:in_stock]
    assert_equal "0", raw[:stock_quantity]
    assert_equal "中文 & Café", raw[:title]
  end

  test "structure changes are parse errors while missing fields remain visible for validation" do
    assert_raises(Scraping::ParseError) { @parser.catalogue("<html></html>", url: @url) }
    assert_raises(Scraping::ParseError) { @parser.book("<html></html>", url: @url) }
    assert_nil @parser.book(@book.sub(/<p class="price_color">.*?<\/p>/m, ""), url: @url)[:price]
    assert_nil @parser.book(@book.sub("star-rating Three", "star-rating Unknown"), url: @url)[:rating]
    assert_nil @parser.book(@book.sub("<th>UPC</th>", "<th>Other</th>"), url: @url)[:upc]
  end

  test "unknown quantity is null and is never inferred from stock flag" do
    raw = @parser.book(@book.sub("In stock (22 available)", "In stock"), url: @url)
    assert raw[:in_stock]
    assert_nil raw[:stock_quantity]
  end

  test "links to other hosts are parse errors" do
    html = @catalogue.sub('href="catalogue/a-light-in-the-attic_1000/index.html" title=', 'href="https://example.com/book" title=')
    assert_raises(Scraping::ParseError) { @parser.catalogue(html, url: BooksToScrape::Url::BASE) }
  end
end
