module Scraping
  class BookRepository
    class IdentityConflict < StandardError; end

    def prepare!
      # Establish replacement uniqueness before removing the old URL constraint.
      Book.create_indexes
      Book.collection.indexes.to_a.each do |index|
        if index["key"] == { "url" => 1 } && index["unique"]
          Book.collection.indexes.drop_one(index.fetch("name"))
        end
      end
    end

    def upsert_from_scrape!(attributes)
      record = Book.new(attributes)
      raise Mongoid::Errors::Validations.new(record) unless record.valid?
      identity = { source: record.source, upc: record.upc }
      existing = Book.collection.find(identity).first
      legacy_filter = {
        url: record.url,
        "$and" => [
          { "$or" => [{ source: nil }, { source: record.source }] },
          { "$or" => [{ upc: nil }, { upc: "" }] }
        ]
      }
      legacy = Book.collection.find(legacy_filter).limit(2).to_a
      if legacy.length > 1 || (existing && legacy.any? { |document| document["_id"] != existing["_id"] })
        raise IdentityConflict, "Ambiguous legacy URL/UPC match; preserved all documents: #{record.url}"
      end

      now = Time.current
      values = record.attributes.slice(*Book::SCRAPED_FIELDS)
      changes = { "$set" => values.merge("updated_at" => now, "last_scraped_at" => now) }
      if legacy.one?
        # Claim only a still-legacy document; concurrent runs cannot overwrite another identity.
        claimed = Book.collection.find(legacy_filter.merge(_id: legacy.first.fetch("_id"))).update_one(changes)
        return if claimed.matched_count == 1
      end
      changes["$setOnInsert"] = { "created_at" => now }
      begin
        Book.collection.find(identity).update_one(changes, upsert: true)
      rescue Mongo::Error::OperationFailure => error
        raise unless error.code == 11000
        # Another writer may have inserted the same identity after our read.
        updated = Book.collection.find(identity).update_one(changes.except("$setOnInsert"))
        raise if updated.matched_count.zero?
      end
    end
  end
end
