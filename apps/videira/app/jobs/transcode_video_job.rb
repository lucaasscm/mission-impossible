require "tmpdir"

class TranscodeVideoJob < ApplicationJob
  queue_as :default

  retry_on VideoTranscoder::OperationalError, wait: :polynomially_longer, attempts: 3 do |job, error|
    if video = Video.find_by(id: job.arguments.first)
      VideoProcessing.new(video).fail_owned_by(job_id: job.job_id, reason: error.message)
    end
  end

  def perform(video_id)
    video = Video.find(video_id)
    processing = VideoProcessing.new(video)
    token = processing.claim(job_id: job_id)
    return unless token

    transcode(video, processing, token)
  rescue VideoTranscoder::UnsupportedMediaError => error
    processing&.fail(token: token, reason: error.message) if token
  rescue ActiveStorage::FileNotFoundError, ActiveStorage::IntegrityError, IOError, SystemCallError => error
    raise VideoTranscoder::OperationalError, error.message
  end

  private
    def transcode(video, processing, token)
      blob = nil
      published = false

      with_lease_heartbeat(processing, token) do
        Dir.mktmpdir([ "video-transcode-", video.id.to_s ], Rails.root.join("tmp")) do |directory|
          output_path = Pathname(directory).join("#{token}.mp4")

          video.file.open do |input|
            VideoTranscoder.new(input_path: input.path, output_path: output_path).call
          end

          next unless processing.renew(token: token)

          blob = ActiveStorage::Blob.create_and_upload!(
            io: output_path.open("rb"),
            filename: "video-#{video.id}-#{token}.mp4",
            content_type: "video/mp4",
            identify: false
          )
          published = processing.publish(blob: blob, token: token)
        end
      end
    ensure
      purge_unpublished_blob(blob) if blob && !published
    end

    def with_lease_heartbeat(processing, token)
      mutex = Mutex.new
      condition = ConditionVariable.new
      stopped = false
      heartbeat = Thread.new do
        loop do
          should_stop = mutex.synchronize do
            condition.wait(mutex, VideoProcessing::HEARTBEAT_INTERVAL) unless stopped
            stopped
          end
          break if should_stop
          break unless renew_lease(processing, token)
        end
      end

      yield
    ensure
      if heartbeat
        mutex.synchronize do
          stopped = true
          condition.signal
        end
        heartbeat.join
      end
    end

    def renew_lease(processing, token)
      ActiveRecord::Base.connection_pool.with_connection do
        processing.renew(token: token)
      end
    rescue StandardError => error
      Rails.logger.error("Could not renew processing lease: #{error.message}")
      true
    end

    def purge_unpublished_blob(blob)
      blob.purge
    rescue StandardError => error
      Rails.logger.error("Could not purge unpublished transcoding blob #{blob.id}: #{error.message}")
    end
end
