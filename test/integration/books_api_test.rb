require "test_helper"

class BooksApiTest < ActionDispatch::IntegrationTest
  include BookTestData
  setup { Book.delete_all }

  test "combined filters include boundary prices and ratings" do
    matching = save_book
    save_book(url: "https://books.toscrape.com/catalogue/expensive/index.html", price_cents: 2000)
    save_book(url: "https://books.toscrape.com/catalogue/low-rating/index.html", rating: 2)
    save_book(url: "https://books.toscrape.com/catalogue/unavailable/index.html", in_stock: false)
    save_book(url: "https://books.toscrape.com/catalogue/poetry/index.html", category: "Poetry")
    get "/api/v1/books", params: { max_price: "19.99", min_rating: "5", in_stock: "true", category: "Fantasy" }
    assert_response :success
    assert_equal [matching.id.to_s], response.parsed_body["data"].map { |book| book["id"] }
    assert_equal 19.99, response.parsed_body["data"].first["price"]
    assert_equal 1, response.parsed_body["meta"]["total"]
  end

  test "false in_stock is an actual filter" do
    save_book
    unavailable = save_book(url: "https://books.toscrape.com/catalogue/unavailable/index.html", in_stock: false)
    get "/api/v1/books", params: { in_stock: "false" }
    assert_response :success
    assert_equal [unavailable.id.to_s], response.parsed_body["data"].map { |book| book["id"] }
  end

  test "pagination has stable URL ordering and metadata" do
    save_book(url: "https://books.toscrape.com/catalogue/b/index.html", title: "B")
    save_book(url: "https://books.toscrape.com/catalogue/a/index.html", title: "A")
    get "/api/v1/books", params: { page: "2", per_page: "1" }
    assert_response :success
    assert_equal ["B"], response.parsed_body["data"].map { |book| book["title"] }
    assert_equal({ "page" => 2, "per_page" => 1, "total" => 2, "total_pages" => 2 }, response.parsed_body["meta"])
  end

  test "show returns JSON for one book" do
    book = save_book
    get "/api/v1/books/#{book.id}"
    assert_response :success
    assert_equal book.id.to_s, response.parsed_body["data"]["id"]
    assert_equal "GBP", response.parsed_body["data"]["currency"]
    assert_equal "示例 Book", response.parsed_body["data"]["title"]
  end

  test "invalid and missing IDs return JSON 404" do
    ["not-an-id", BSON::ObjectId.new.to_s].each do |id|
      get "/api/v1/books/#{id}"
      assert_response :not_found
      assert_equal "Book not found", response.parsed_body["error"]
    end
  end

  test "invalid scalar array and operator parameters return JSON 400" do
    [{ max_price: "abc" }, { max_price: "-1" }, { min_rating: "6" },
     { in_stock: "yes" }, { page: "0" }, { per_page: "101" },
     { category: { "$ne" => "Poetry" } }, { min_rating: ["1", "2"] }].each do |params|
      get "/api/v1/books", params: params
      assert_response :bad_request
      assert response.parsed_body["error"].present?
    end
  end

  test "page beyond results returns an empty JSON list" do
    save_book
    get "/api/v1/books", params: { page: "3", per_page: "1" }
    assert_response :success
    assert_empty response.parsed_body["data"]
    assert_equal 1, response.parsed_body["meta"]["total"]
  end

  test "min price is inclusive and combines with max price" do
    matching = save_book(price_cents: 1999)
    save_book(url: "https://books.toscrape.com/catalogue/cheap/index.html", price_cents: 1998)
    get "/api/v1/books", params: { min_price: "19.99", max_price: "19.99" }
    assert_response :success
    assert_equal [matching.id.to_s], response.parsed_body["data"].map { |book| book["id"] }
  end

  test "all six sort options are allowed and use stable ID tie breaks" do
    first = save_book(title: "A", price_cents: 1000, rating: 1)
    second = save_book(url: "https://books.toscrape.com/catalogue/b/index.html", title: "B", price_cents: 2000, rating: 5)
    third = save_book(url: "https://books.toscrape.com/catalogue/c/index.html", title: "B", price_cents: 2000, rating: 5)
    ties = [second.id.to_s, third.id.to_s].sort
    %w[price rating title].each do |field|
      { "asc" => [first.id.to_s, *ties], "desc" => [*ties, first.id.to_s] }.each do |direction, expected|
        ids = (1..3).map do |page|
          get "/api/v1/books", params: { sort: "#{field}_#{direction}", per_page: "1", page: page.to_s }
          assert_response :success
          response.parsed_body.fetch("data").first.fetch("id")
        end
        assert_equal expected, ids
      end
    end
  end

  test "sort injection unknown fields and invalid price ranges return 400" do
    [{ sort: "url_asc" }, { sort: "price;drop" }, { sort: { "$where" => "x" } },
     { min_price: "abc" }, { min_price: "-1" }, { min_price: "2", max_price: "1" }].each do |params|
      get "/api/v1/books", params: params
      assert_response :bad_request
    end
  end
end
