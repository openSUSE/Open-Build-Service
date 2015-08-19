class AddIndexForBinaryReleases < ActiveRecord::Migration
  def self.up
    add_index :binary_releases, [:binary_name, :binary_arch]

    # fix request prio table, it could have been a string before
    execute("UPDATE bs_requests SET priority = 'moderate' WHERE ISNULL(priority) or priority='';")
    execute("alter table bs_requests modify column `priority` enum('critical','important','moderate','low') DEFAULT 'moderate';")
  end

  def self.down
    remove_index :binary_releases, [:binary_name, :binary_arch]
  end
end
