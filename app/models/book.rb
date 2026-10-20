class Book
  include Mongoid::Document
  include Mongoid::Timestamps

  SCRAPED_FIELDS = %w[source upc title price_cents currency rating in_stock stock_quantity url category].freeze
  field :source, type: String
  field :upc, type: String

  field :title, type: String
  field :price_cents, type: Integer
  field :currency, type: String, default: "GBP"
  field :rating, type: Integer
  field :in_stock, type: Mongoid::Boolean
  field :stock_quantity, type: Integer
  field :url, type: String
  field :category, type: String
  field :last_scraped_at, type: Time

  index({ source: 1, upc: 1 }, unique: true,
        partial_filter_expression: { source: { "$type" => "string" }, upc: { "$type" => "string" } })
  index({ url: 1 }, name: "book_url_lookup")
  index({ category: 1 })

  validates :source, :upc, :title, :url, :category, presence: true
  validates :price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :rating, inclusion: { in: 1..5 }
  validates :in_stock, inclusion: { in: [true, false] }
  validates :stock_quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :currency, format: { with: /\A[A-Z]{3}\z/ }
  validate :allowed_url

  def self.upsert_from_scrape!(attributes)
    Scraping::BookRepository.new.upsert_from_scrape!(attributes)
  end

  private

  def allowed_url
    uri = URI.parse(url.to_s)
    errors.add(:url, "must be an absolute HTTPS URL") unless uri.is_a?(URI::HTTPS) && uri.host.present? && !uri.userinfo
  rescue ArgumentError, URI::InvalidURIError, TypeError
    errors.add(:url, "must be an absolute HTTPS URL")
  end
end
