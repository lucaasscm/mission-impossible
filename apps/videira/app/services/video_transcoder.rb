require "open3"

class VideoTranscoder
  class Error < StandardError; end
  class UnsupportedMediaError < Error; end
  class OperationalError < Error; end

  OPERATIONAL_FAILURE_PATTERN = Regexp.union(
    /no space left on device/i,
    /permission denied/i,
    /input\/output error/i,
    /cannot allocate memory/i,
    /resource temporarily unavailable/i
  )

  def initialize(input_path:, output_path:, runner: Open3.method(:capture3))
    @input_path = input_path
    @output_path = output_path
    @runner = runner
  end

  def call
    _stdout, stderr, status = runner.call(*command)
    return output_path if status.success? && File.exist?(output_path)

    error_class = stderr.match?(OPERATIONAL_FAILURE_PATTERN) ? OperationalError : UnsupportedMediaError
    raise error_class, failure_message(stderr)
  rescue SystemCallError => error
    raise OperationalError, "Could not run ffmpeg: #{error.message}"
  end

  private
    attr_reader :input_path, :output_path, :runner

    def command
      [
        "ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
        "-i", input_path.to_s,
        "-map", "0:v:0", "-map", "0:a:0?",
        "-c:v", "libx264", "-preset", "medium", "-crf", "23",
        "-pix_fmt", "yuv420p",
        "-c:a", "aac", "-b:a", "128k",
        "-movflags", "+faststart",
        output_path.to_s
      ]
    end

    def failure_message(stderr)
      details = stderr.lines.last(20).join.strip
      details.present? ? details : "ffmpeg exited without producing an output file"
    end
end
