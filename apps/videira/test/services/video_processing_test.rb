require "test_helper"

class VideoProcessingTest < ActiveSupport::TestCase
  setup do
    @video = videos(:one)
    @video.file.attach(io: file_fixture("sample.mp4").open, filename: "sample.mp4", content_type: "video/mp4")
    @processing = VideoProcessing.new(@video)
  end

  test "only one job can claim a fresh video" do
    now = Time.current

    first_token = @processing.claim(job_id: "job-1", now: now)
    second_token = @processing.claim(job_id: "job-2", now: now + 1.second)

    assert first_token
    assert_nil second_token
  end

  test "the same retried job can renew its claim immediately" do
    now = Time.current
    first_token = @processing.claim(job_id: "job-1", now: now)
    retry_token = @processing.claim(job_id: "job-1", now: now + 1.second)

    assert first_token
    assert retry_token
    refute_equal first_token, retry_token
  end

  test "a stale worker cannot publish after a new worker reclaims the video" do
    now = Time.current
    stale_token = @processing.claim(job_id: "job-1", now: now)
    winning_token = @processing.claim(
      job_id: "job-2",
      now: now + VideoProcessing::LEASE_DURATION + 1.second
    )
    stale_blob = create_blob("stale")
    winning_blob = create_blob("winner")

    refute @processing.publish(blob: stale_blob, token: stale_token)
    assert @processing.publish(blob: winning_blob, token: winning_token)

    @video.reload
    assert @video.ready?
    assert_equal winning_blob, @video.playback_file.blob
  ensure
    stale_blob&.purge
  end

  test "only the claim owner can record a terminal failure" do
    token = @processing.claim(job_id: "job-1")

    refute @processing.fail(token: "another-token", reason: "wrong worker")
    assert @processing.fail(token: token, reason: "unsupported codec")
    assert @video.reload.failed?
    assert_equal "unsupported codec", @video.failure_reason
  end

  test "only the claim owner can renew the processing lease" do
    token = @processing.claim(job_id: "job-1", now: 1.minute.ago)
    heartbeat_at = Time.current

    refute @processing.renew(token: "another-token", now: heartbeat_at)
    assert @processing.renew(token: token, now: heartbeat_at)
    assert_in_delta heartbeat_at, @video.reload.processing_heartbeat_at, 0.001
  end

  test "an expired lease can be requeued but a current lease cannot" do
    now = Time.current
    @processing.claim(job_id: "job-1", now: now)

    refute @processing.requeue_if_expired(now: now + VideoProcessing::LEASE_DURATION - 1.second)
    assert @processing.requeue_if_expired(now: now + VideoProcessing::LEASE_DURATION + 1.second)
    assert @video.reload.queued?
    assert_nil @video.processing_token
  end

  private
    def create_blob(contents)
      ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(contents),
        filename: "#{contents}.mp4",
        content_type: "video/mp4",
        identify: false
      )
    end
end
