require "test_helper"

class VideoTest < ActiveSupport::TestCase
  test "new videos start queued" do
    video = users(:one).videos.new(title: "Queued", file: file_fixture("sample.mp4").open)

    assert video.queued?
  end
end
