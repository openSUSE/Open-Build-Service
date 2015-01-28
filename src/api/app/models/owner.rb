# -*- encoding: utf-8 i*-
require 'api_exception'

class Owner

  class AttributeNotSetError < APIException
    setup 'attribute_not_set', 400
  end

  def self.attribute_names
    [:rootproject, :project, :package, :filter, :users, :groups]
  end

  include ActiveModel::Model
  attr_accessor(*attribute_names)

  def to_hash
    # The same implemented as one-liner, but code climate doesn't like
    # Hash[*(Owner.attribute_names.map {|a| [a, send(a)] }.select {|a| !a.last.nil? }.flatten(1))]
    hash = {}
    Owner.attribute_names.map do |a|
      unless (value = send(a)).nil?
        hash[a] = value
      end
    end
    hash
  end

  def self.search(params, obj)
    params[:attribute] ||= "OBS:OwnerRootProject"
    at = AttribType.find_by_name!(params[:attribute])

    limit  = params[:limit] || 1

    projects = []
    if obj.is_a? Project
      projects = [obj]
    elsif obj.is_a? Package
      projects = [obj.project]
    elsif params[:project]
      # default project specified
      projects = [Project.get_by_name(params[:project])]
    else
      # Find all marked projects
      projects = Project.find_by_attribute_type(at)
      if projects.empty?
        raise(AttributeNotSetError,
              "The attribute type #{params[:attribute]} is not set on any projects. No default projects defined.")
      end
    end

    # search in each marked project
    owners = []
    projects.each do |project|

      attrib = project.attribs.where(attrib_type_id: at.id).first
      filter = %w(maintainer bugowner)
      devel  = true
      if params[:filter]
        filter=params[:filter].split(",")
      else
        if attrib and v=attrib.values.where(value: "BugownerOnly").exists?
          filter=%w(bugowner)
        end
      end
      if params[:devel]
        devel=false if %w(0 false).include? params[:devel]
      else
        if attrib and v=attrib.values.where(value: "DisableDevel").exists?
          devel=false
        end
      end

      if obj.nil?
        owners += self.find_containers_without_definition(project, devel, filter)
      elsif obj.is_a? String
        owners += self.find_assignees(project, obj, limit.to_i, devel,
                                                filter, (true unless params[:webui_mode].blank?))
      elsif obj.is_a? Project or obj.is_a? Package
        owners += self.find_maintainers(obj, filter)
      else
        owners += self.find_containers(project, obj, devel, filter)
      end

    end

    return owners
  end

  protected

  def self.find_assignees(rootproject, binary_name, limit=1, devel=true, filter=%w(maintainer bugowner), webui_mode=false)
    projects=rootproject.expand_all_projects
    instances_without_definition=[]
    maintainers=[]
    pkg=nil

    match_all = (limit == 0)
    deepest = (limit < 0)

    # binary search via all projects
    prjlist = projects.map { |p| "@project='#{CGI.escape(p.name)}'" }
    path = "/search/published/binary/id?match=(@name='"+CGI.escape(binary_name)+"'"
    path += "+and+("
    path += prjlist.join("+or+")
    path += "))"
    answer = Suse::Backend.post path, nil
    data = Xmlhash.parse(answer.body)
    # found binary package?
    return [] if data["matches"].to_i == 0

    already_checked = {}
    deepest_match = nil
    projects.each do |prj| # project link order
      data.elements("binary").each do |b| # no order
        next unless b["project"] == prj.name

        pkg = prj.packages.find_by_name( b["package"] )
        next if pkg.nil?

        # the "" means any matching relationships will get taken
        m, limit, already_checked = self.lookup_package_owner(rootproject, pkg, "", limit, devel, filter, deepest, already_checked)

        unless m
          # collect all no matched entries
          m = Owner.new(rootproject: rootproject.name, project: pkg.project.name, package: pkg.name, filter: filter)
          instances_without_definition << m
          next
        end

        # remember as deepest candidate
        if deepest == true
          deepest_match = m
          next
        end

        # add matching entry
        maintainers << m
        limit = limit - 1
        return maintainers if limit < 1 and not match_all
      end
    end

    return instances_without_definition if webui_mode and maintainers.length < 1

    maintainers << deepest_match if deepest_match

    return maintainers
  end

  def self.find_containers_without_definition(rootproject, devel=true, filter=%w(maintainer bugowner))
    projects=rootproject.expand_all_projects
    roles=[]
    filter.each do |f|
      roles << Role.find_by_title!(f)
    end

    # fast find packages with defintions
    # relationship in package object
    defined_packages = Package.where(project_id: projects).joins(:relationships => :user).where(["relationships.role_id IN (?) AND (ISNULL(user_id) OR users.state = ?)", roles, User.states['confirmed']]).pluck(:name)
    # relationship in project object
    Project.joins(:relationships => :user).where("projects.id in (?) AND role_id in (?) AND (ISNULL(user_id) OR users.state = ?)", projects, roles, User.states['confirmed']).each do |prj|
      defined_packages += prj.packages.map{ |p| p.name }
    end
    if devel == true
      #FIXME add devel packages, but how do recursive lookup fast in SQL?
    end
    defined_packages.uniq!

    all_packages = Package.where(project_id: projects).pluck(:name)

    undefined_packages = all_packages - defined_packages
    maintainers=[]

    undefined_packages.each do |p|
      next if p =~ /\A_product:\w[-+\w\.]*\z/

      pkg = rootproject.find_package(p)

      m = Owner.new
      m.rootproject = rootproject.name
      m.project = pkg.project.name
      m.package = pkg.name

      maintainers << m
    end

    return maintainers
  end

  def self.find_containers(rootproject, owner, devel=true, filter=%w(maintainer bugowner))
    projects=rootproject.expand_all_projects

    roles=[]
    filter.each do |f|
      roles << Role.find_by_title!(f)
    end

    found_packages = Relationship.where(role_id: roles, package_id: Package.where(project_id: projects).pluck(:id))
    found_projects = Relationship.where(role_id: roles, project_id: projects)
    # fast find packages with defintions
    if owner.class == User
      # user in package object
      found_packages = found_packages.where(user_id: owner)
      # user in project object
      found_projects = found_projects.where(user_id: owner)
    elsif owner.class == Group
      # group in package object
      found_packages = found_packages.where(group_id: owner)
      # group in project object
      found_projects = found_projects.where(group_id: owner)
    else
      raise "illegal object handed to find_containers"
    end
    if devel == true
      #FIXME add devel packages, but how do recursive lookup fast in SQL?
    end
    found_packages = found_packages.pluck(:package_id).uniq
    found_projects = found_projects.pluck(:project_id).uniq

    maintainers=[]

    Project.where(id: found_projects).pluck(:name).each do |prj|
      maintainers << Owner.new(rootproject: rootproject.name, project: prj)
    end
    Package.where(id: found_packages).each do |pkg|
      maintainers << Owner.new(rootproject: rootproject.name, project: pkg.project.name, package: pkg.name)
    end

    return maintainers
  end

  def self.find_maintainers(container, filter)
    maintainers = []
    sql = self._build_rolefilter_sql(filter)
    add_owners = Proc.new {|cont|
      m = Owner.new
      m.rootproject = ''
      if cont.is_a? Package
        m.project = cont.project.name
        m.package = cont.name 
      else
        m.project = cont.name
      end
      m.filter = filter
      self._extract_from_container(m, cont.relationships, sql, nil)
      maintainers << m unless m.users.nil? and m.groups.nil?
    }
    project = container
    if container.is_a? Package
      add_owners.call container
      project = container.project
    end
    # add maintainers from parent projects
    while not project.nil?
      add_owners.call(project)
      project = project.find_parent
    end
    maintainers
  end

  def self.lookup_package_owner(rootproject, pkg, owner, limit, devel, filter, deepest, already_checked={})
    return nil, limit, already_checked if already_checked[pkg.id]

    # optional check for devel package instance first
    m = nil
    m = self.extract_maintainer(rootproject, pkg.resolve_devel_package, filter, owner) if devel == true
    m = self.extract_maintainer(rootproject, pkg, filter, owner) unless m

    already_checked[pkg.id] = 1

    # found entry
    return m, (limit-1), already_checked if m

    # no match, loop about projects below with this package container name
    pkg.project.expand_all_projects.each do |prj|
      p = prj.packages.find_by_name(pkg.name )
      next if p.nil? or already_checked[p.id]

      already_checked[p.id] = 1

      m = self.extract_maintainer(rootproject, p.resolve_devel_package, filter, owner) if devel == true
      m = self.extract_maintainer(rootproject, p, filter, owner) unless m

      break unless deepest if m
    end

    # found entry
    return m, (limit-1), already_checked
  end

  def self.extract_maintainer(rootproject, pkg, rolefilter, objfilter=nil)
    return nil unless pkg
    return nil unless Package.check_access?(pkg)
    m = Owner.new

    m.rootproject = rootproject.name
    m.project = pkg.project.name
    m.package = pkg.name
    m.filter = rolefilter

    # no filter defined, so do not check for roles and just return container
    return m if rolefilter.empty?
    sql = self._build_rolefilter_sql(rolefilter)
    # lookup in package container
    m = self._extract_from_container(m, pkg.relationships, sql, objfilter)

    # did it it match? if not fallback to project level
    unless m.users or m.groups
      m.package = nil
      m = self._extract_from_container(m, pkg.project.relationships, sql, objfilter)
    end
    # still not matched? Ignore it
    return nil unless m.users or m.groups

    return m
  end

  private
  def self._extract_from_container(m, r, sql, objfilter)
    usersql = groupsql = sql
    usersql  = sql << " AND user_id = " << objfilter.id.to_s  if objfilter.class == User
    groupsql = sql << " AND group_id = " << objfilter.id.to_s if objfilter.class == Group

    r.users.where(usersql).each do |p|
      next unless p.user.state == User.states['confirmed']
      m.users ||= {}
      m.users[p.role.title] ||= []
      m.users[p.role.title] << p.user.login
    end unless objfilter.class == Group

    r.groups.where(groupsql).each do |p|
      next unless p.group.users.where(state: User.states['confirmed']).length > 0
      m.groups ||= {}
      m.groups[p.role.title] ||= []
      m.groups[p.role.title] << p.group.title
    end unless objfilter.class == User
    return m
  end

  def self._build_rolefilter_sql(rolefilter)
    # construct where condition
    sql = nil
    if rolefilter.length > 0
      rolefilter.each do |rf|
       if sql.nil?
         sql = "( "
       else
         sql << " OR "
       end
       role = Role.find_by_title!(rf)
       sql << "role_id = " << role.id.to_s
      end
    else
      # match all roles
      sql = "( 1 "
    end
    sql << " )"
  end

end
