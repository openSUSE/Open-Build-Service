class AddTitleToBsRequest < ActiveRecord::Migration[7.0]
  def change
    add_column :bs_requests, :title, :string
  end
end
