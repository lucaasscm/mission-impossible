class Video < ApplicationRecord
  belongs_to :user
  has_one_attached :file
  has_one_attached :playback_file

  enum :status, {
    queued: "queued",
    processing: "processing",
    ready: "ready",
    failed: "failed"
  }, default: :queued, validate: true

  validates :title, presence: true
  validates :file, presence: true
end
