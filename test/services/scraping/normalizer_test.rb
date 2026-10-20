require "test_helper"

class NormalizerTest < ActiveSupport::TestCase
  setup do
    @normalizer = Scraping::Normalizer.new(source: "books_to_scrape", url_policy: BooksToScrape::Url)
    @raw = BooksToScrape::Parser.new.book(file_fixture("book.html").read,
                                        url: "https://books.toscrape.com/catalogue/a-light-in-the-attic_1000/index.html")
  end

  test "normalizes strings prices quantities and URLs to independent typed records" do
    book = @normalizer.call(@raw.merge(title: "  A  Book  ", price: "19.9", url: "#{@raw[:url]}?tracking=1#about"))
    assert_equal 1990, book[:price_cents]
    assert_equal 3, book[:rating]
    assert_equal 22, book[:stock_quantity]
    assert_equal "A Book", book[:title]
    assert_equal @raw[:url], book[:url]
    assert_equal "books_to_scrape", book[:source]
    assert book.frozen?
  end

  test "absent critical fields produce explicit validation errors" do
    %i[price rating upc].each do |field|
      error = assert_raises(Scraping::ValidationError) { @normalizer.call(@raw.merge(field => nil)) }
      assert_includes error.fields, field
    end
  end

  test "malformed numeric and boolean values are not silently coerced" do
    [{ price: "USD 51.77" }, { price: "-1" }, { price: "1.001" }, { rating: "3abc" },
     { rating: 6 }, { stock_quantity: "many" }, { in_stock: nil }, { stock_quantity: -1 }].each do |changes|
      assert_raises(Scraping::ValidationError) { @normalizer.call(@raw.merge(changes)) }
    end
  end

  test "nullable quantity and explicit zero remain distinct" do
    assert_nil @normalizer.call(@raw.merge(stock_quantity: nil))[:stock_quantity]
    assert_equal 0, @normalizer.call(@raw.merge(stock_quantity: "0", in_stock: false))[:stock_quantity]
    assert_raises(Scraping::ValidationError) { @normalizer.call(@raw.merge(stock_quantity: "0", in_stock: true)) }
  end
end
