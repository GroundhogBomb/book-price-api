module Api
  module V1
    class BookSerializer
      # v1 is additive only. Do not rename/remove fields or change existing types.
      def self.call(book)
        {
          id: book.id.to_s, title: book.title, price: book.price_cents&./(100.0),
          currency: book.currency, rating: book.rating, in_stock: book.in_stock,
          url: book.url, category: book.category, last_scraped_at: book.last_scraped_at&.iso8601,
          source: book.source, upc: book.upc, stock_quantity: book.stock_quantity
        }
      end
    end
  end
end
