class VideosController < ApplicationController
  allow_unauthenticated_access only: %i[index show status]

  def index
    @videos = Video.order(created_at: :desc)
  end

  def show
    @video = Video.find(params[:id])
  end

  def status
    video = Video.find(params[:id])
    expires_now
    render json: { status: video.status }
  end

  def new
    @video = Video.new
  end

  def create
    @video = Current.user.videos.new(video_params)
    if @video.save
      enqueue_transcoding
      redirect_to @video, notice: "Video uploaded. Processing will continue in the background."
    else
      render :new, status: :unprocessable_entity
    end
  end

  private
    def video_params
      params.expect(video: [ :title, :file ])
    end

    def enqueue_transcoding
      job = TranscodeVideoJob.perform_later(@video.id)
      Rails.logger.error("Could not enqueue video #{@video.id}") unless job
    rescue ActiveJob::EnqueueError => error
      Rails.logger.error("Could not enqueue video #{@video.id}: #{error.message}")
    end
end
