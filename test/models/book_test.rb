require "test_helper"

class BookTest < ActiveSupport::TestCase
  include BookTestData
  setup do
    Book.delete_all
    @repository = Scraping::BookRepository.new
    @repository.prepare!
  end
  teardown { @repository.prepare! }

  test "same source and UPC updates one document even when URL changes" do
    first = save_book
    created_at = first.created_at
    Book.upsert_from_scrape!(attributes_for_book(upc: first.upc, price_cents: 1234, title: "Updated",
                                               url: "https://books.toscrape.com/catalogue/renamed/index.html"))
    assert_equal 1, Book.count
    book = Book.first
    assert_equal first.id, book.id
    assert_equal 1234, book.price_cents
    assert_equal "Updated", book.title
    assert_equal created_at, book.created_at
    assert book.last_scraped_at
  end

  test "database unique compound index rejects same identity but permits other sources" do
    first = save_book
    assert_raises(Mongo::Error::OperationFailure) do
      Book.collection.insert_one(attributes_for_book(upc: first.upc, url: "https://books.toscrape.com/catalogue/another/index.html"))
    end
    Book.collection.insert_one(attributes_for_book(source: "another_source", upc: first.upc))
    assert_equal 2, Book.count
  end

  test "legacy documents without identities coexist and URL adoption retains ID and creation time" do
    now = Time.current.change(usec: 0)
    old = attributes_for_book.except(:source, :upc, :stock_quantity).merge(created_at: now)
    id = Book.collection.insert_one(old).inserted_id
    Book.collection.insert_one(old.merge(url: "https://books.toscrape.com/catalogue/other-legacy/index.html"))
    Book.upsert_from_scrape!(attributes_for_book)
    Book.upsert_from_scrape!(attributes_for_book(price_cents: 1500))
    assert_equal 2, Book.count
    adopted = Book.find(id)
    assert_equal "books_to_scrape", adopted.source
    assert_equal attributes_for_book[:upc], adopted.upc
    assert_equal now, adopted.created_at
    assert_equal 1500, adopted.price_cents
  end

  test "index preparation replaces legacy URL uniqueness without deleting documents" do
    old = attributes_for_book.except(:source, :upc, :stock_quantity)
    id = Book.collection.insert_one(old).inserted_id
    Book.collection.indexes.create_one({ url: 1 }, unique: true, name: "url_1")
    @repository.prepare!
    @repository.prepare!
    assert_equal id, Book.first.id
    refute Book.collection.indexes.to_a.any? { |index| index["key"] == { "url" => 1 } && index["unique"] }
    assert Book.collection.indexes.to_a.any? { |index| index["key"] == { "source" => 1, "upc" => 1 } && index["unique"] }
  end

  test "ambiguous legacy identities preserve every existing document" do
    old = attributes_for_book.except(:source, :upc)
    2.times { Book.collection.insert_one(old) }
    before = Book.collection.find.to_a
    assert_raises(Scraping::BookRepository::IdentityConflict) { Book.upsert_from_scrape!(attributes_for_book) }
    assert_equal before, Book.collection.find.to_a
  end

  test "invalid records cannot be stored through persistence" do
    assert_raises(Mongoid::Errors::Validations) { Book.upsert_from_scrape!(attributes_for_book(rating: 6)) }
    assert_raises(Mongoid::Errors::Validations) { Book.upsert_from_scrape!(attributes_for_book(price_cents: -1)) }
    assert_raises(Mongoid::Errors::Validations) { Book.upsert_from_scrape!(attributes_for_book(stock_quantity: -1)) }
    assert_equal 0, Book.count
  end
end
