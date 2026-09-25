class AddProcessingStateToVideos < ActiveRecord::Migration[8.1]
  def change
    add_column :videos, :status, :string, null: false, default: "queued"
    add_column :videos, :processing_token, :string
    add_column :videos, :processing_job_id, :string
    add_column :videos, :processing_started_at, :datetime
    add_column :videos, :failure_reason, :text

    add_index :videos, :status
    add_index :videos, :processing_started_at
  end
end
