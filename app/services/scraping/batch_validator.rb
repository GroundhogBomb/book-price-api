module Scraping
  class BatchValidator
    CRITICAL_FIELDS = %i[price rating upc].freeze
    Result = Data.define(:accepted, :reasons, :warnings)

    def initialize(critical_rejection_ratio:, expected_page_size:)
      unless critical_rejection_ratio.is_a?(Numeric) && critical_rejection_ratio.positive? && critical_rejection_ratio <= 1
        raise ArgumentError, "critical_rejection_ratio must be in (0, 1]"
      end
      @ratio, @expected_page_size = critical_rejection_ratio, expected_page_size
    end

    # Evaluate the entire page before any book is persisted.
    def call(item_count:, fetched_count:, records:, validation_errors:, parse_errors:)
      reasons, warnings = [], []
      warnings << "Expected about #{@expected_page_size} books, got #{item_count}; page size is advisory" if item_count != @expected_page_size
      reasons << "Catalogue contains zero books" if item_count.zero?
      reasons << "Detail page structure changed (#{parse_errors.length} parse errors)" if parse_errors.any?
      critical = validation_errors.count { |error| (error.fields & CRITICAL_FIELDS).any? }
      if fetched_count.positive? && critical.fdiv(fetched_count) >= @ratio
        reasons << "Critical fields invalid/missing in #{critical}/#{fetched_count} fetched details (threshold #{@ratio})"
      end
      reasons << "No validated books available" if records.empty?
      Result.new(accepted: reasons.empty?, reasons: reasons.freeze, warnings: warnings.freeze)
    end
  end
end
