class AddProcessingHeartbeatToVideos < ActiveRecord::Migration[8.1]
  def change
    add_column :videos, :processing_heartbeat_at, :datetime
    add_index :videos, :processing_heartbeat_at
  end
end
