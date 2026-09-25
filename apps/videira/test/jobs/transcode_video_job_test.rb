require "test_helper"

class TranscodeVideoJobTest < ActiveJob::TestCase
  setup do
    @video = videos(:one)
    @video.file.attach(io: file_fixture("sample.mp4").open, filename: "sample.mp4", content_type: "video/mp4")
  end

  test "publishes a unique playback file and marks the video ready" do
    TranscodeVideoJob.perform_now(@video.id)

    @video.reload
    assert @video.ready?
    assert @video.playback_file.attached?
    assert_match(/video-#{@video.id}-[0-9a-f-]+\.mp4/, @video.playback_file.filename.to_s)
    assert_nil @video.processing_token
  end

  test "unsupported media is terminal and preserves the original" do
    @video.file.attach(
      io: StringIO.new("this is not a video"),
      filename: "broken.mov",
      content_type: "video/quicktime"
    )

    TranscodeVideoJob.perform_now(@video.id)

    @video.reload
    assert @video.failed?
    assert_match(/Invalid data/, @video.failure_reason)
    assert @video.file.attached?
    refute @video.playback_file.attached?
  end

  test "a missing source file is retried as an operational failure" do
    @video.file.blob.service.delete(@video.file.key)

    assert_enqueued_with(job: TranscodeVideoJob, args: [ @video.id ]) do
      TranscodeVideoJob.perform_now(@video.id)
    end

    assert @video.reload.processing?
    refute @video.playback_file.attached?
  end
end
