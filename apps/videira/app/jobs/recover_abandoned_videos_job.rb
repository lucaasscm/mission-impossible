class RecoverAbandonedVideosJob < ApplicationJob
  queue_as :maintenance

  ENQUEUE_GRACE_PERIOD = 1.minute

  def perform(now = Time.current)
    recover_expired_processing(now)
    recover_unenqueued_videos(now)
  end

  private
    def recover_expired_processing(now)
      expired_before = now - VideoProcessing::LEASE_DURATION

      Video.processing
        .where("processing_heartbeat_at IS NULL OR processing_heartbeat_at < ?", expired_before)
        .find_each do |video|
          enqueue(video) if VideoProcessing.new(video).requeue_if_expired(now: now)
        end
    end

    def recover_unenqueued_videos(now)
      Video.queued.where(updated_at: ..(now - ENQUEUE_GRACE_PERIOD)).find_each do |video|
        enqueue(video)
      end
    end

    def enqueue(video)
      job = TranscodeVideoJob.perform_later(video.id)
      Rails.logger.error("Could not re-enqueue video #{video.id}") unless job
    rescue ActiveJob::EnqueueError => error
      Rails.logger.error("Could not re-enqueue video #{video.id}: #{error.message}")
    end
end
