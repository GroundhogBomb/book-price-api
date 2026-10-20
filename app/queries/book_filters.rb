require "bigdecimal"

class BookFilters
  class InvalidParameter < StandardError; end

  SORTS = {
    "price_asc" => { price_cents: :asc }, "price_desc" => { price_cents: :desc },
    "rating_asc" => { rating: :asc }, "rating_desc" => { rating: :desc },
    "title_asc" => { title: :asc }, "title_desc" => { title: :desc }
  }.freeze

  attr_reader :page, :per_page, :order

  def initialize(params)
    @params = params
    @page = integer("page", default: 1, range: 1..1_000_000)
    @per_page = integer("per_page", default: 20, range: 1..100)
    @order = if @params.key?("sort")
      SORTS.fetch(scalar("sort")) { invalid!("sort", "must be one of #{SORTS.keys.join(', ')}") }
    else
      { url: :asc }
    end.merge(_id: :asc)
  end

  def apply(scope)
    minimum = amount("min_price") if @params.key?("min_price")
    maximum = amount("max_price") if @params.key?("max_price")
    invalid!("min_price", "must not exceed max_price") if minimum && maximum && minimum > maximum
    scope = scope.where(:price_cents.gte => minimum) if minimum
    scope = scope.where(:price_cents.lte => maximum) if maximum
    if @params.key?("min_rating")
      scope = scope.where(:rating.gte => integer("min_rating", range: 1..5))
    end
    if @params.key?("in_stock")
      value = scalar("in_stock")
      invalid!("in_stock", "must be true or false") unless %w[true false].include?(value)
      scope = scope.where(in_stock: value == "true")
    end
    if @params.key?("category")
      value = scalar("category").strip
      invalid!("category", "must be a nonempty string up to 100 characters") unless value.length.between?(1, 100)
      scope = scope.where(category: value)
    end
    scope
  end

  private

  def amount(name)
    value = scalar(name)
    invalid!(name, "must be a nonnegative GBP amount with at most 2 decimals") unless /\A\d{1,8}(?:\.\d{1,2})?\z/.match?(value)
    (BigDecimal(value) * 100).to_i
  end

  def integer(name, default: nil, range:)
    return default unless @params.key?(name)
    value = scalar(name)
    invalid!(name, "must be an integer in #{range}") unless /\A\d{1,7}\z/.match?(value) && range.cover?(value.to_i)
    value.to_i
  end

  def scalar(name)
    value = @params[name]
    invalid!(name, "must be a scalar string") unless value.is_a?(String)
    value
  end

  def invalid!(name, message)
    raise InvalidParameter, "#{name} #{message}"
  end
end
