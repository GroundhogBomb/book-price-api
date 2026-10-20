module Api
  module V1
    class BooksController < ApplicationController
      rescue_from BookFilters::InvalidParameter do |error|
        render json: { error: error.message }, status: :bad_request
      end
      rescue_from Mongo::Error do |error|
        Rails.logger.error("books API database error=#{error.class}")
        render json: { error: "Database unavailable; start MongoDB and try again" }, status: :service_unavailable
      end

      def index
        filters = BookFilters.new(params)
        scope = filters.apply(Book.all)
        total = scope.count
        books = scope.order_by(filters.order).skip((filters.page - 1) * filters.per_page).limit(filters.per_page)
        render json: {
          data: books.map { |book| BookSerializer.call(book) },
          meta: { page: filters.page, per_page: filters.per_page, total: total,
                  total_pages: (total.to_f / filters.per_page).ceil }
        }
      end

      def show
        id = params[:id]
        book = Book.where(id: BSON::ObjectId.from_string(id)).first if BSON::ObjectId.legal?(id)
        return render json: { error: "Book not found" }, status: :not_found unless book
        render json: { data: BookSerializer.call(book) }
      end
    end
  end
end
