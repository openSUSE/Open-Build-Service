class PackageGroupRoleRelationship < ActiveRecord::Base
  belongs_to :package, foreign_key: :db_package_id
  belongs_to :group, foreign_key: "bs_group_id"
  belongs_to :role

  has_many :groups_users, through: :group

  validates :group, presence: true
  validates :package, presence: true
  validates :role, presence: true

  validate :check_uniqueness
  protected
  def check_uniqueness
    if PackageGroupRoleRelationship.where("db_package_id = ? AND role_id = ? AND bs_group_id = ?", self.package, self.role, self.group).first
      errors.add(:role, "Group already has this role")
    end
  end
end
