require "yaml"

module Scraping
  class Settings
    KEYS = %i[open_timeout read_timeout write_timeout max_attempts interval user_agent max_pages critical_rejection_ratio expected_page_size].freeze
    attr_reader(*KEYS)

    def self.load(source, env: ENV)
      values = YAML.safe_load_file(Rails.root.join("config/scraping.yml")).fetch(source).symbolize_keys
      if env.key?("MAX_PAGES")
        value = env.fetch("MAX_PAGES")
        raise ArgumentError, "MAX_PAGES must be a positive integer" unless /\A[1-9]\d*\z/.match?(value)
        values[:max_pages] = value.to_i
      end
      new(**values)
    end

    def initialize(**values)
      KEYS.each { |key| instance_variable_set("@#{key}", values.fetch(key)) }
      %i[open_timeout read_timeout write_timeout].each do |key|
        raise ArgumentError, "#{key} must be positive" unless public_send(key).is_a?(Numeric) && public_send(key).positive?
      end
      raise ArgumentError, "interval must be at least 1 second" unless interval.is_a?(Numeric) && interval >= 1
      raise ArgumentError, "max_attempts must be a positive integer" unless max_attempts.is_a?(Integer) && max_attempts.positive?
      raise ArgumentError, "max_pages must be null or a positive integer" unless max_pages.nil? || (max_pages.is_a?(Integer) && max_pages.positive?)
      raise ArgumentError, "user_agent is required" if user_agent.to_s.strip.empty? || user_agent.match?(/[\r\n]/)
      unless critical_rejection_ratio.is_a?(Numeric) && critical_rejection_ratio.positive? && critical_rejection_ratio <= 1
        raise ArgumentError, "critical_rejection_ratio must be in (0, 1]"
      end
      raise ArgumentError, "expected_page_size must be a positive integer" unless expected_page_size.is_a?(Integer) && expected_page_size.positive?
      freeze
    end

    def with(**overrides)
      self.class.new(**KEYS.to_h { |key| [key, public_send(key)] }.merge(overrides))
    end
  end
end
