require "set"

module Scraping
  class Runner
    FAILURE_KINDS = %w[network parse validation persistence internal].freeze

    def initialize(source:, start_url:, fetcher:, parser:, normalizer:, batch_validator:, settings:,
                   repository: BookRepository.new, recorder: RunRecorder.new, logger: Rails.logger)
      @source, @start_url, @fetcher, @parser = source, start_url, fetcher, parser
      @normalizer, @batch_validator, @settings = normalizer, batch_validator, settings
      @repository, @recorder, @logger = repository, recorder, logger
    end

    def call(max_pages: @settings.max_pages)
      unless max_pages.nil? || (max_pages.is_a?(Integer) && max_pages.positive?)
        raise ArgumentError, "max_pages must be null or a positive integer"
      end
      result = { pages_fetched: 0, books_saved: 0, batches_rejected: 0, failures: [], warnings: [],
                 failure_counts: FAILURE_KINDS.to_h { |kind| [kind, 0] }, limited: false }
      run = @recorder.start(source: @source, settings: @settings.with(max_pages: max_pages))
      failed = false
      begin
        @repository.prepare!
        pages_seen, books_seen = Set.new, Set.new
        page_url = @start_url
        while page_url
          if pages_seen.include?(page_url)
            failure(result, "parse", page_url, "Pagination cycle detected", scope: "page")
            failed = true
            break
          end
          pages_seen.add(page_url)
          begin
            html = @fetcher.get(page_url)
            result[:pages_fetched] += 1
            page = @parser.catalogue(html, url: page_url)
          rescue NetworkError => e
            failure(result, "network", page_url, e.message, scope: "page", attempts: e.attempts)
            failed = true
            break
          rescue ParseError => e
            failure(result, "parse", page_url, e.message, scope: "page")
            reject_batch(result, page_url, "Catalogue structure invalid; no books written")
            failed = true
            break
          end
          process_batch(page, page_url, books_seen, result)
          page_url = page.fetch(:next_url)
          if max_pages && result[:pages_fetched] >= max_pages
            result[:limited] = !page_url.nil?
            break
          end
        end
      rescue Mongo::Error => e
        failure(result, "persistence", @start_url, "#{e.class}: #{e.message}", scope: "run")
        failed = true
      rescue StandardError => e
        failure(result, "internal", @start_url, "#{e.class}: #{e.message}", scope: "run")
        failed = true
        raise
      ensure
        @recorder.finish(run, result, failed: failed || !$!.nil?)
      end
      result.merge(run_id: run.id.to_s)
    end

    private

    def process_batch(page, page_url, books_seen, result)
      urls = page.fetch(:book_urls)
      return if urls.any? && urls.all? { |url| books_seen.include?(url) }
      records, validation_errors, parse_errors = [], [], []
      fetched_count = 0
      urls.each do |url|
        next if books_seen.include?(url)
        begin
          html = @fetcher.get(url)
          fetched_count += 1
          raw = @parser.book(html, url: url)
          records << @normalizer.call(raw)
        rescue NetworkError => e
          failure(result, "network", url, e.message, scope: "book", attempts: e.attempts)
        rescue ParseError => e
          parse_errors << e
          failure(result, "parse", url, e.message, scope: "book")
        rescue ValidationError => e
          validation_errors << e
          failure(result, "validation", url, e.message, scope: "book", fields: e.fields)
        end
      end
      batch = @batch_validator.call(item_count: urls.length, fetched_count: fetched_count,
                                    records: records, validation_errors: validation_errors, parse_errors: parse_errors)
      batch.warnings.each do |message|
        result[:warnings] << { url: page_url, reason: message }
        @logger.warn("batch url=#{page_url} warning=#{message}")
      end
      return reject_batch(result, page_url, batch.reasons.join("; ")) unless batch.accepted

      # All page parsing/normalization and the guard above have completed before the first write.
      records.each do |attributes|
        begin
          @repository.upsert_from_scrape!(attributes)
          result[:books_saved] += 1
          books_seen.add(attributes.fetch(:url))
        rescue BookRepository::IdentityConflict, Mongoid::Errors::Validations, Mongo::Error => e
          failure(result, "persistence", attributes.fetch(:url), "#{e.class}: #{e.message}", scope: "book")
        end
      end
    end

    def reject_batch(result, url, reason)
      result[:batches_rejected] += 1
      failure(result, "validation", url, reason, scope: "batch")
    end

    def failure(result, kind, url, reason, **details)
      result[:failure_counts][kind] += 1
      result[:failures] << { kind: kind, url: url, reason: reason }.merge(details)
      @logger.error("scrape kind=#{kind} url=#{url} reason=#{reason}")
    end
  end
end
