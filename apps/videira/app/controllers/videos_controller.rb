class VideosController < ApplicationController
  allow_unauthenticated_access only: %i[index show]

  def index
    @videos = Video.order(created_at: :desc)
  end

  def show
    @video = Video.find(params[:id])
  end

  def new
    @video = Video.new
  end

  def create
    @video = Current.user.videos.new(video_params)
    if @video.save
      redirect_to @video, notice: "Video published."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def video_params
      params.expect(video: [ :title, :file ])
    end
end
