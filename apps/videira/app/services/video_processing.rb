class VideoProcessing
  LEASE_DURATION = 1.minute
  HEARTBEAT_INTERVAL = 15.seconds

  def initialize(video)
    @video = video
  end

  def claim(job_id:, now: Time.current)
    token = SecureRandom.uuid
    expired_before = now - LEASE_DURATION

    claimed = Video
      .where(id: video.id)
      .where(
        <<~SQL.squish,
          status = :queued OR (
            status = :processing AND (
              processing_job_id = :job_id OR
              processing_heartbeat_at IS NULL OR
              processing_heartbeat_at < :expired_before
            )
          )
        SQL
        queued: "queued",
        processing: "processing",
        job_id: job_id,
        expired_before: expired_before
      )
      .update_all(
        status: "processing",
        processing_token: token,
        processing_job_id: job_id,
        processing_started_at: now,
        processing_heartbeat_at: now,
        failure_reason: nil,
        updated_at: now
      )

    token if claimed == 1
  end

  def renew(token:, now: Time.current)
    Video
      .where(id: video.id, status: "processing", processing_token: token)
      .update_all(processing_heartbeat_at: now) == 1
  end

  def requeue_if_expired(now: Time.current)
    expired_before = now - LEASE_DURATION

    Video
      .where(id: video.id, status: "processing")
      .where("processing_heartbeat_at IS NULL OR processing_heartbeat_at < ?", expired_before)
      .update_all(
        status: "queued",
        processing_token: nil,
        processing_job_id: nil,
        processing_started_at: nil,
        processing_heartbeat_at: nil,
        failure_reason: nil,
        updated_at: now
      ) == 1
  end

  def publish(blob:, token:)
    video.with_lock do
      next false unless owned_by_token?(token)

      video.playback_file.attach(blob)
      video.update!(status: :ready, **cleared_processing_attributes, failure_reason: nil)
      true
    end
  end

  def fail(token:, reason:)
    video.with_lock do
      next false unless owned_by_token?(token)

      video.update!(
        status: :failed,
        **cleared_processing_attributes,
        failure_reason: reason.to_s.truncate(2_000)
      )
      true
    end
  end

  def fail_owned_by(job_id:, reason:)
    video.with_lock do
      next false unless video.processing? && video.processing_job_id == job_id

      video.update!(
        status: :failed,
        **cleared_processing_attributes,
        failure_reason: reason.to_s.truncate(2_000)
      )
      true
    end
  end

  private
    attr_reader :video

    def owned_by_token?(token)
      video.processing? && video.processing_token == token
    end

    def cleared_processing_attributes
      {
        processing_token: nil,
        processing_job_id: nil,
        processing_started_at: nil,
        processing_heartbeat_at: nil
      }
    end
end
