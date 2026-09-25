namespace :videos do
  desc "Enqueue videos left queued after a process crash or queue outage"
  task enqueue_queued: :environment do
    count = 0

    Video.queued.find_each do |video|
      TranscodeVideoJob.perform_later(video.id)
      count += 1
    rescue ActiveJob::EnqueueError => error
      warn "Could not enqueue video #{video.id}: #{error.message}"
    end

    puts "Enqueued #{count} queued video(s)."
  end
end
