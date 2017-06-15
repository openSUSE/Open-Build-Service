# A project that has a remote url set
class RemoteProject < Project
  validates :title, :description, :remoteurl, presence: true
  validate :exists_by_name_validation

  def exists_by_name_validation
    return unless Project.exists_by_name(name)
    errors.add(:name, 'already exists.')
  end
end

# == Schema Information
#
# Table name: projects
#
#  id              :integer          not null, primary key
#  name            :string(200)      not null, indexed
#  title           :string(255)
#  description     :text(65535)
#  created_at      :datetime
#  updated_at      :datetime         indexed
#  remoteurl       :string(255)
#  remoteproject   :string(255)
#  develproject_id :integer          indexed
#  delta           :boolean          default(TRUE), not null
#  url             :string(255)
#  kind            :integer          default("standard")
#
# Indexes
#
#  devel_project_id_index  (develproject_id)
#  projects_name_index     (name) UNIQUE
#  updated_at_index        (updated_at)
#
