class AddOriginForAcceptinfo < ActiveRecord::Migration
  def self.up
    add_column :bs_request_action_accept_infos, :oproject, :string
    add_column :bs_request_action_accept_infos, :opackage, :string
  end

  def self.down
    remove_column :bs_request_action_accept_infos, :oproject
    remove_column :bs_request_action_accept_infos, :opackage
  end
end
