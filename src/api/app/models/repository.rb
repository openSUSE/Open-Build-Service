class Repository < ActiveRecord::Base

  belongs_to :project, foreign_key: :db_project_id, inverse_of: :repositories

  before_destroy :cleanup_before_destroy

  has_many :channel_targets, :class_name => "ChannelTarget", :dependent => :delete_all, :foreign_key => 'repository_id'
  has_many :release_targets, :class_name => "ReleaseTarget", :dependent => :delete_all, :foreign_key => 'repository_id'
  has_many :path_elements, -> { order("position") }, foreign_key: 'parent_id', dependent: :delete_all, inverse_of: :repository
  has_many :links, :class_name => "PathElement", :foreign_key => 'repository_id', inverse_of: :link
  has_many :targetlinks, :class_name => "ReleaseTarget", :foreign_key => 'target_repository_id'
  has_many :download_stats
  has_one :hostsystem, :class_name => "Repository", :foreign_key => 'hostsystem_id'
  has_many :binary_releases, :dependent => :destroy
  has_many :product_update_repositories, dependent: :delete_all
  has_many :product_medium, dependent: :delete_all
  has_many :repository_architectures, -> { order("position") }, :dependent => :destroy, inverse_of: :repository
  has_many :architectures, -> { order("position") }, :through => :repository_architectures

  scope :not_remote, -> { where(:remote_project_name => nil) }

  validate :validate_duplicates, :on => :create
  def validate_duplicates
    if Repository.where("db_project_id = ? AND name = ? AND ( remote_project_name = ? OR remote_project_name is NULL)", self.db_project_id, self.name, self.remote_project_name).first
      errors.add(:project, "already has repository with name #{self.name}")
    end
  end

  def cleanup_before_destroy
    # change all linking repository pathes
    self.linking_repositories.each do |lrep|
      lrep.path_elements.includes(:link, :repository).each do |pe|
        next unless pe.link == self # this is not pointing to our repo
        if lrep.path_elements.where(repository_id: Repository.deleted_instance).size > 0
          # repo has already a path element pointing to deleted repository
          pe.destroy 
        else
          pe.link = Repository.deleted_instance
          pe.save
        end
      end
      lrep.project.store({:lowprio => true})
    end
    # target repos
    logger.debug "remove target repositories from repository #{self.project.name}/#{self.name}"
    self.linking_target_repositories.each do |lrep|
      lrep.targetlinks.includes(:target_repository, :repository).each do |rt|
        next unless rt.target_repository == self # this is not pointing to our repo
        repo = rt.repository
        if lrep.targetlinks.where(repository_id: Repository.deleted_instance).size > 0
          # repo has already a path element pointing to deleted repository
          logger.debug "destroy release target #{rt.target_repository.project.name}/#{rt.target_repository.name}"
          rt.destroy 
        else
          logger.debug "set deleted repo for releasetarget #{rt.target_repository.project.name}/#{rt.target_repository.name}"
          rt.target_repository = Repository.deleted_instance
          rt.save
        end
        repo.project.store({:lowprio => true})
      end
    end
  end

  class << self
    def find_by_project_and_repo_name( project, repo )
      result = not_remote.joins(:project).where(:projects => {:name => project}, :name => repo).first
      return result unless result.nil?

      #no local repository found, check if remote repo possible

      local_project, remote_project = Project.find_remote_project(project)
      if local_project
        return local_project.repositories.find_or_create_by(name: repo, remote_project_name: remote_project)
      end

      return nil
    end

    def deleted_instance
      repo = Repository.find_by_project_and_repo_name( "deleted", "deleted" )
      return repo unless repo.nil?

      # does not exist, so let's create it
      project = Project.deleted_instance
      project.repositories.find_or_create_by(name: "deleted")
    end
  end

  #returns a list of repositories that include path_elements linking to this one
  #or empty list
  def linking_repositories
    return [] if links.size == 0
    links.map {|l| l.repository}
  end

  def linking_target_repositories
    return [] if targetlinks.size == 0
    targetlinks.map {|l| l.target_repository}
  end

  def extended_name
    longName = self.project.name.gsub(':', '_')
    if self.project.repositories.count > 1
      # keep short names if project has just one repo
      longName += '_'+self.name unless self.name == 'standard'
    end
    return longName
  end

  def to_axml_id
    return "<repository project='#{::Builder::XChar.encode(project.name)}' name='#{::Builder::XChar.encode(name)}'/>\n"
  end

  def to_s
    name
  end

  def download_medium_url(medium)
    Rails.cache.fetch("download_url_#{self.project.name}##{self.name}##medium##{medium}") do
      path  = "/published/#{URI.escape(self.project.name)}/#{URI.escape(self.name)}"
      path += "?view=publishedpath"
      path += "&medium=#{CGI.escape(file)}"
      xml = Xmlhash.parse(Suse::Backend.get(path).body)
      xml.elements('url').last.to_s
    end
  end

  def download_url(file)
    url = Rails.cache.fetch("download_url_#{self.project.name}##{self.name}") do
      path  = "/published/#{URI.escape(self.project.name)}/#{URI.escape(self.name)}"
      path += "?view=publishedpath"
      xml = Xmlhash.parse(Suse::Backend.get(path).body)
      xml.elements('url').last.to_s
    end
    url += "/" + file unless file.blank?
  end

  def download_url_for_package(package, architecture, filename)
    Rails.cache.fetch("download_url_for_package_#{self.project.name}##{self.name}##{package.name}##{architecture}##{filename}") do
      path  = "/build/#{URI.escape(self.project.name)}/#{URI.escape(self.name)}/#{URI.escape(architecture)}/#{URI.escape(package.name)}/#{URI.escape(filename)}"
      path += "?view=publishedpath"
      xml = Xmlhash.parse(Suse::Backend.get(path).body)
      xml.elements('url').last.to_s
    end
  end
end
