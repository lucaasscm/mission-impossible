require "test_helper"

class RecoverAbandonedVideosJobTest < ActiveJob::TestCase
  setup do
    @video = videos(:one)
    @video.file.attach(io: file_fixture("sample.mp4").open, filename: "sample.mp4", content_type: "video/mp4")
  end

  test "requeues and enqueues processing whose lease expired" do
    now = Time.current
    VideoProcessing.new(@video).claim(
      job_id: "dead-job",
      now: now - VideoProcessing::LEASE_DURATION - 1.second
    )

    assert_enqueued_with(job: TranscodeVideoJob, args: [ @video.id ]) do
      RecoverAbandonedVideosJob.perform_now(now)
    end

    assert @video.reload.queued?
    assert_nil @video.processing_token
  end

  test "leaves active processing alone" do
    now = Time.current
    VideoProcessing.new(@video).claim(job_id: "live-job", now: now)

    assert_no_enqueued_jobs do
      RecoverAbandonedVideosJob.perform_now(now)
    end

    assert @video.reload.processing?
  end

  test "recovers queued videos left behind by an enqueue crash" do
    now = Time.current
    @video.update_column(:updated_at, now - RecoverAbandonedVideosJob::ENQUEUE_GRACE_PERIOD - 1.second)

    assert_enqueued_with(job: TranscodeVideoJob, args: [ @video.id ]) do
      RecoverAbandonedVideosJob.perform_now(now)
    end

    assert @video.reload.queued?
  end
end
