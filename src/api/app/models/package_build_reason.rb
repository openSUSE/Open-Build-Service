class PackageBuildReason
  include ActiveModel::Model

  validates :explain, :time, presence: true
  attr_accessor :explain, :time, :oldsource, :packagechange
end
