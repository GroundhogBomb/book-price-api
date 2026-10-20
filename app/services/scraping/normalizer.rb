module Scraping
  class Normalizer
    def initialize(source:, url_policy:)
      @source, @url_policy = source, url_policy
    end

    # Input is a site-independent raw field Hash from Parser; output is a typed Hash.
    # No HTML, networking or database access belongs in this layer.
    def call(raw)
      errors = {}
      values = { source: @source }
      %i[title category upc].each do |field|
        value = raw[field]
        values[field] = value.is_a?(String) ? value.gsub(/\s+/, " ").strip : nil
        errors[field] = "is required" if values[field].to_s.empty?
      end
      if values[:upc].present? && !/\A[A-Za-z0-9_-]{1,128}\z/.match?(values[:upc])
        errors[:upc] = "must be a nonempty identifier up to 128 characters"
      end
      amount = raw[:price].is_a?(String) && raw[:price].strip.match(/\A(\d{1,8})(?:\.(\d{1,2}))?\z/)
      if amount
        values[:price_cents] = amount[1].to_i * 100 + amount[2].to_s.ljust(2, "0").to_i
      else
        errors[:price] = "must be a nonnegative amount with at most 2 decimals"
      end
      values[:currency] = raw[:currency]&.strip&.upcase if raw[:currency].is_a?(String)
      errors[:currency] = "must be a three-letter currency code" unless /\A[A-Z]{3}\z/.match?(values[:currency].to_s)
      rating = raw[:rating]
      if (rating.is_a?(String) || rating.is_a?(Integer)) && /\A[1-5]\z/.match?(rating.to_s)
        values[:rating] = rating.to_i
      else
        errors[:rating] = "must be an integer from 1 to 5"
      end
      values[:in_stock] = case raw[:in_stock]
      when true, "true" then true
      when false, "false" then false
      else errors[:in_stock] = "must be true or false"; nil
      end
      quantity = raw[:stock_quantity]
      if quantity.nil?
        values[:stock_quantity] = nil
      elsif (quantity.is_a?(String) || quantity.is_a?(Integer)) && /\A\d+\z/.match?(quantity.to_s)
        values[:stock_quantity] = quantity.to_i
      else
        errors[:stock_quantity] = "must be null or a nonnegative integer"
      end
      if values[:stock_quantity] && !values[:in_stock].nil? && (values[:stock_quantity].positive? != values[:in_stock])
        errors[:stock_quantity] = "conflicts with in_stock"
      end
      begin
        raise ArgumentError, "URL is required" unless raw[:url].is_a?(String) && raw[:url].present?
        values[:url] = @url_policy.normalize(raw[:url])
      rescue ArgumentError, URI::InvalidURIError => e
        errors[:url] = e.message
      end
      if errors.any?
        raise ValidationError.new(errors.map { |field, reason| "#{field} #{reason}" }.join("; "), fields: errors.keys)
      end
      values.freeze
    end
  end
end
