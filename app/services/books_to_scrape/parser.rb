require "nokogiri"

module BooksToScrape
  class Parser
    ParseError = Scraping::ParseError
    RATINGS = { "One" => "1", "Two" => "2", "Three" => "3", "Four" => "4", "Five" => "5" }.freeze

    def catalogue(html, url:)
      document = Nokogiri::HTML(html, nil, "UTF-8")
      links = document.css("article.product_pod h3 a")
      raise ParseError, "Catalogue has no book links; check page structure" if links.empty?
      next_link = document.at_css("li.next a")
      {
        book_urls: links.map { |link| Url.normalize(required_attribute(link, "href"), base: url) }.uniq,
        next_url: next_link && Url.normalize(required_attribute(next_link, "href"), base: url)
      }
    rescue ArgumentError, URI::InvalidURIError => e
      raise ParseError, e.message
    end

    def book(html, url:)
      document = Nokogiri::HTML(html, nil, "UTF-8")
      main = document.at_css(".product_main")
      raise ParseError, "Missing product details; check page structure" unless main
      amount = text(main.at_css(".price_color"))
      availability = text(main.at_css(".availability"))
      rating = main.at_css(".star-rating")&.[]("class").to_s.split.filter_map { |name| RATINGS[name] }.first
      category_links = document.css(".breadcrumb li a")
      upc_row = document.css("table tr").find { |row| text(row.at_css("th")) == "UPC" }
      {
        title: text(main.at_css("h1")),
        price: amount&.delete_prefix("£"), currency: amount&.start_with?("£") ? "GBP" : nil,
        rating: rating, upc: text(upc_row&.at_css("td"))&.downcase,
        in_stock: case availability
                  when /\AIn stock\b/i then true
                  when /\AOut of stock\b/i then false
                  end,
        stock_quantity: availability&.match(/\((\d+) available\)/i)&.[](1),
        url: url, category: category_links.length >= 3 ? text(category_links.last) : nil
      }
    end

    private

    def text(node)
      value = node&.text&.gsub(/\s+/, " ")&.strip
      value.presence
    end

    def required_attribute(node, name)
      value = node[name]
      raise ParseError, "Missing #{name}" if value.to_s.strip.empty?
      value
    end
  end
end
