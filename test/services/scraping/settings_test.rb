require "test_helper"

class ScrapingSettingsTest < ActiveSupport::TestCase
  test "settings are centralized and page override is strictly positive" do
    settings = Scraping::Settings.load("books_to_scrape", env: { "MAX_PAGES" => "2" })
    assert_equal 2, settings.max_pages
    assert_operator settings.interval, :>=, 1
    assert settings.user_agent.include?("BookPriceAPI")
    assert_equal 0.25, settings.critical_rejection_ratio
    ["0", "-1", "2.5", "abc", ""].each do |value|
      assert_raises(ArgumentError) { Scraping::Settings.load("books_to_scrape", env: { "MAX_PAGES" => value }) }
    end
    assert_raises(ArgumentError) { settings.with(interval: 0.1) }
    assert_raises(ArgumentError) { settings.with(critical_rejection_ratio: 0) }
  end
end
