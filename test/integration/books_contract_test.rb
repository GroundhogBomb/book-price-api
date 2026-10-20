require "test_helper"

class BooksContractTest < ActionDispatch::IntegrationTest
  include BookTestData
  FIELDS = %w[id title price currency rating in_stock url category last_scraped_at source upc stock_quantity].sort.freeze
  setup { Book.delete_all }

  test "v1 list and detail lock the public output fields and types" do
    book = save_book
    get "/api/v1/books"
    assert_response :success
    assert_equal %w[data meta], response.parsed_body.keys.sort
    assert_equal %w[page per_page total total_pages], response.parsed_body["meta"].keys.sort
    assert_equal FIELDS, response.parsed_body["data"].first.keys.sort
    get "/api/v1/books/#{book.id}"
    assert_response :success
    data = response.parsed_body.fetch("data")
    assert_equal FIELDS, data.keys.sort
    %w[id title currency url category source upc last_scraped_at].each { |key| assert_kind_of String, data.fetch(key) }
    assert_kind_of Numeric, data.fetch("price")
    assert_kind_of Integer, data.fetch("rating")
    assert_kind_of Integer, data.fetch("stock_quantity")
    assert_includes [true, false], data.fetch("in_stock")
  end

  test "old documents return the same fields with null new values" do
    values = attributes_for_book.except(:source, :upc, :stock_quantity)
    id = Book.collection.insert_one(values).inserted_id
    get "/api/v1/books/#{id}"
    assert_response :success
    data = response.parsed_body.fetch("data")
    assert_equal FIELDS, data.keys.sort
    %w[source upc stock_quantity].each { |key| assert_nil data.fetch(key) }
    assert_equal "示例 Book", data["title"]
    get "/api/v1/books"
    assert_response :success
    assert_nil response.parsed_body["data"].first.fetch("upc")
  end

  test "unversioned routes are removed" do
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/api/books", method: :get)
    end
    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path("/api/books/#{BSON::ObjectId.new}", method: :get)
    end
  end
end
