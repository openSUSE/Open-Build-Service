#
class BsRequestActionAddRole < BsRequestAction
  #### Includes and extends
  #### Constants
  #### Self config
  #### Attributes
  #### Associations macros (Belongs to, Has one, Has many)
  #### Callbacks macros: before_save, after_save, etc.
  #### Scopes (first the default_scope macro if is used)
  #### Validations macros

  #### Class methods using self. (public and then private)
  def self.sti_name
    :add_role
  end

  #### To define class methods as private use private_class_method
  #### private

  #### Instance methods (public and then protected/private)
  def check_sanity
    super
    errors.add(:role, "should not be empty for add_role") if role.blank?
    return unless person_name.blank? && group_name.blank?
    errors.add(:person_name, "Either person or group needs to be set")
  end

  def execute_accept(_opts)
    object = Project.find_by_name(target_project)
    if target_package
      object = object.packages.find_by_name(target_package)
    end
    if person_name
      role = Role.find_by_title!(self.role)
      object.add_user( person_name, role )
    end
    if group_name
      role = Role.find_by_title!(self.role)
      object.add_group( group_name, role )
    end
    object.store(comment: "add_role request #{bs_request.number}", request: bs_request)
  end

  def render_xml_attributes(node)
    render_xml_target(node)
    if person_name
      node.person name: person_name, role: role
    end
    return unless group_name

    node.group name: group_name, role: role
  end

  #### Alias of methods
end

# == Schema Information
#
# Table name: bs_request_actions
#
#  id                    :integer          not null, primary key
#  bs_request_id         :integer          indexed
#  type                  :string(255)
#  target_project        :string(255)      indexed
#  target_package        :string(255)      indexed
#  target_releaseproject :string(255)
#  source_project        :string(255)      indexed
#  source_package        :string(255)      indexed
#  source_rev            :string(255)
#  sourceupdate          :string(255)
#  updatelink            :boolean          default(FALSE)
#  person_name           :string(255)
#  group_name            :string(255)
#  role                  :string(255)
#  created_at            :datetime
#  target_repository     :string(255)
#  makeoriginolder       :boolean          default(FALSE)
#  target_type           :string(255)      indexed => [target_id]
#  target_id             :integer          indexed => [target_type]
#  source_type           :string(255)      indexed => [source_id]
#  source_id             :integer          indexed => [source_type]
#
# Indexes
#
#  bs_request_id                                          (bs_request_id)
#  index_bs_request_actions_on_source_package             (source_package)
#  index_bs_request_actions_on_source_project             (source_project)
#  index_bs_request_actions_on_source_type_and_source_id  (source_type,source_id)
#  index_bs_request_actions_on_target_package             (target_package)
#  index_bs_request_actions_on_target_project             (target_project)
#  index_bs_request_actions_on_target_type_and_target_id  (target_type,target_id)
#
# Foreign Keys
#
#  bs_request_actions_ibfk_1  (bs_request_id => bs_requests.id)
#
