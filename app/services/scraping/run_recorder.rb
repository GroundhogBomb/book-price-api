module Scraping
  class RunRecorder
    def start(source:, settings:)
      ScrapeRun.create!(source: source, started_at: Time.current,
                        settings_snapshot: Settings::KEYS.to_h { |key| [key.to_s, settings.public_send(key)] })
    end

    def finish(run, result, failed: false)
      status = if failed
        "failed"
      elsif result.fetch(:failures).any?
        "completed_with_errors"
      else
        "completed"
      end
      run.set(result.slice(:pages_fetched, :books_saved, :batches_rejected, :failure_counts, :failures, :warnings, :limited)
                    .merge(status: status, finished_at: Time.current))
    end
  end
end
