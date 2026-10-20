class ScrapeRun
  include Mongoid::Document

  field :source, type: String
  field :started_at, type: Time
  field :finished_at, type: Time
  field :status, type: String, default: "running"
  field :pages_fetched, type: Integer, default: 0
  field :books_saved, type: Integer, default: 0
  field :batches_rejected, type: Integer, default: 0
  field :failure_counts, type: Hash, default: -> { {} }
  field :failures, type: Array, default: -> { [] }
  field :warnings, type: Array, default: -> { [] }
  field :limited, type: Mongoid::Boolean, default: false
  field :settings_snapshot, type: Hash

  validates :source, :started_at, presence: true
  validates :status, inclusion: { in: %w[running completed completed_with_errors failed] }
end
