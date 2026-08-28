require "test_helper"

class VideosControllerTest < ActionDispatch::IntegrationTest
  setup do
    @video = videos(:one)
    @video.file.attach(io: file_fixture("sample.mp4").open, filename: "sample.mp4", content_type: "video/mp4")
  end

  test "index and show are public" do
    get root_url
    assert_response :success
    assert_select "a", @video.title

    get video_url(@video)
    assert_response :success
    assert_select "video[controls]"
  end

  test "publishing requires sign in" do
    get new_video_url
    assert_redirected_to new_session_url
  end

  test "create attaches the uploaded file" do
    sign_in_as users(:one)
    assert_difference("Video.count") do
      post videos_url, params: { video: { title: "Upload", file: fixture_file_upload("sample.mp4", "video/mp4") } }
    end
    assert_redirected_to video_url(Video.last)
    assert Video.last.file.attached?
  end

  test "create without a file re-renders the form" do
    sign_in_as users(:one)
    assert_no_difference("Video.count") do
      post videos_url, params: { video: { title: "No file" } }
    end
    assert_response :unprocessable_entity
  end
end
