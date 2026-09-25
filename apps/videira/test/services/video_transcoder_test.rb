require "test_helper"

class VideoTranscoderTest < ActiveSupport::TestCase
  FakeStatus = Struct.new(:success?)

  test "classifies invalid media as a terminal error" do
    runner = ->(*) { [ "", "Invalid data found when processing input", FakeStatus.new(false) ] }
    error = assert_raises(VideoTranscoder::UnsupportedMediaError) do
      VideoTranscoder.new(input_path: "input.mov", output_path: "output.mp4", runner: runner).call
    end

    assert_match(/Invalid data/, error.message)
  end

  test "classifies infrastructure failures as retryable" do
    runner = ->(*) { [ "", "No space left on device", FakeStatus.new(false) ] }
    assert_raises(VideoTranscoder::OperationalError) do
      VideoTranscoder.new(input_path: "input.mov", output_path: "output.mp4", runner: runner).call
    end
  end

  test "classifies a missing ffmpeg executable as retryable" do
    runner = ->(*) { raise Errno::ENOENT, "ffmpeg" }
    assert_raises(VideoTranscoder::OperationalError) do
      VideoTranscoder.new(input_path: "input.mov", output_path: "output.mp4", runner: runner).call
    end
  end
end
