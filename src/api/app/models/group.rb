require_dependency 'api_exception'

# The Group class represents a group record in the database and thus a group
# in the ActiveRbac model. Groups are arranged in trees and have a title.
# Groups have an arbitrary number of roles and users assigned to them.
#
class Group < ApplicationRecord
  has_one :staging_workflow, class_name: 'Staging::Workflow', foreign_key: :managers_group_id, dependent: :nullify
  has_many :groups_users, inverse_of: :group, dependent: :destroy
  has_many :users, -> { distinct }, through: :groups_users
  has_many :group_maintainers, inverse_of: :group, dependent: :destroy
  has_many :relationships, dependent: :destroy, inverse_of: :group
  has_many :event_subscriptions, dependent: :destroy, inverse_of: :group
  has_many :reviews, dependent: :nullify

  has_many :rss_feed_items, -> { order(created_at: :desc) }, class_name: 'Notification::RssFeedItem', as: :subscriber, dependent: :destroy

  validates :title,
            format: { with: %r{\A[\w\.\-]*\z},
                      message: 'must not contain invalid characters' }
  validates :title,
            length: { in: 2..100,
                      too_long: 'must have less than 100 characters',
                      too_short: 'must have more than two characters',
                      allow_nil: false }
  # We want to validate a group's title pretty thoroughly.
  validates :title,
            uniqueness: { message: 'is the name of an already existing group' }

  # groups have a n:m relation to groups
  has_and_belongs_to_many :roles, -> { distinct }

  default_scope { order(:title) }

  alias_attribute :name, :title

  def self.find_by_title!(title)
    find_by_title(title) || (raise NotFoundError, "Couldn't find Group '#{title}'")
  end

  def update_from_xml(xmlhash)
    with_lock do
      if xmlhash.value('email')
        self.email = xmlhash.value('email')
      else
        self.email = nil
      end
    end
    save!

    # update maintainer list
    cache = group_maintainers.index_by(&:user_id)

    xmlhash.elements('maintainer') do |maintainer|
      next unless maintainer['userid']
      user = User.find_by_login!(maintainer['userid'])
      if cache.key?(user.id)
        # user has already a role in this package
        cache.delete(user.id)
      else
        GroupMaintainer.create(user: user, group: self).save
      end
    end
    cache.each do |login_id, _|
      GroupMaintainer.where('user_id = ? AND group_id = ?', login_id, id).delete_all
    end

    # update user list
    cache = groups_users.index_by(&:user_id)

    persons = xmlhash.elements('person').first
    if persons
      persons.elements('person') do |person|
        next unless person['userid']
        user = User.find_by_login!(person['userid'])
        if cache.key?(user.id)
          # user has already a role in this package
          cache.delete(user.id)
        else
          GroupsUser.create(user: user, group: self).save
        end
      end
    end

    # delete all users which were not listed
    cache.each do |login_id, _gu|
      GroupsUser.where('user_id = ? AND group_id = ?', login_id, id).delete_all
    end
  end

  def add_user(user)
    return if users.find_by_id(user.id) # avoid double creation
    gu = GroupsUser.create(user: user, group: self)
    gu.save!
  end

  def replace_members(members)
    Group.transaction do
      users.delete_all
      members.split(',').each do |m|
        users << User.find_by_login!(m)
      end
      save!
    end
  rescue ActiveRecord::RecordInvalid, NotFoundError => exception
    errors.add(:base, exception.message)
  end

  def remove_user(user)
    GroupsUser.where('user_id = ? AND group_id = ?', user.id, id).delete_all
  end

  def set_email(email)
    self.email = email
    save!
  end

  def to_s
    title
  end

  def to_param
    to_s
  end

  def involved_projects_ids
    # just for maintainer for now.
    role = Role.hashed['maintainer']

    ### all projects where user is maintainer
    Relationship.projects.where(group_id: id, role_id: role.id).distinct.pluck(:project_id)
  end
  protected :involved_projects_ids

  def involved_projects
    # now filter the projects that are not visible
    Project.where(id: involved_projects_ids)
  end

  # lists packages maintained by this user and are not in maintained projects
  def involved_packages
    # just for maintainer for now.
    role = Role.hashed['maintainer']

    projects = involved_projects_ids
    projects << -1 if projects.empty?

    # all packages where group is maintainer
    packages = Relationship.where(group_id: id, role_id: role.id).joins(:package).where('packages.project_id not in (?)', projects).pluck(:package_id)

    Package.where(id: packages).where.not(project_id: projects)
  end

  # returns the users that actually want email for this group's notifications
  def email_users
    User.where(id: groups_users.where(email: true).pluck(:user_id))
  end

  def display_name
    address = Mail::Address.new(email)
    address.display_name = title
    address.format
  end

  def involved_reviews(search = nil)
    BsRequest.find_for(
      group: title,
      roles: [:reviewer],
      review_states: [:new],
      states: [:review],
      search: search
    )
  end

  def incoming_requests(search = nil)
    BsRequest.find_for(group: title, states: [:new], roles: [:maintainer], search: search)
  end

  def requests(search = nil)
    BsRequest.find_for(group: title, search: search)
  end

  def tasks
    Rails.cache.fetch("requests_for_#{cache_key}") do
      incoming_requests.count +
        involved_reviews.count
    end
  end

  def any_confirmed_users?
    !users.where(state: 'confirmed').empty?
  end
end

# == Schema Information
#
# Table name: groups
#
#  id         :integer          not null, primary key
#  created_at :datetime
#  updated_at :datetime
#  title      :string(200)      default(""), not null, indexed
#  parent_id  :integer          indexed
#  email      :string(255)
#
# Indexes
#
#  groups_parent_id_index  (parent_id)
#  index_groups_on_title   (title)
#
