module Maintainership

  def extract_maintainer(rootproject, pkg, rolefilter, objfilter=nil)
    return nil unless pkg
    return nil unless Package.check_access?(pkg)
    m = {}

    m[:rootproject] = rootproject.name
    m[:project] = pkg.project.name
    m[:package] = pkg.name
    m[:filter] = rolefilter

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
    usersql = groupsql = sql
    usersql  = sql << " AND user_id = " << objfilter.id.to_s  if objfilter.class == User
    groupsql = sql << " AND group_id = " << objfilter.id.to_s if objfilter.class == Group

    # lookup
    pkg.relationships.users.where(usersql).each do |p|
      m[:users] ||= {}
      m[:users][p.role.title] ||= []
      m[:users][p.role.title] << p.user.login
    end unless objfilter.class == Group

    pkg.relationships.groups.where(groupsql).each do |p|
      m[:groups] ||= {}
      m[:groups][p.role.title] ||= []
      m[:groups][p.role.title] << p.group.title
    end unless objfilter.class == User

    # did it it match? if not fallback to project level
    unless m[:users] or m[:groups]
      m[:package] = nil
      pkg.project.relationships.users.where(usersql).each do |p|
        m[:users] ||= {}
        m[:users][p.role.title] ||= []
        m[:users][p.role.title] << p.user.login
      end unless objfilter.class == Group

      pkg.project.relationships.groups.where(groupsql).each do |p|
        m[:groups] ||= {}
        m[:groups][p.role.title] ||= []
        m[:groups][p.role.title] << p.group.title
      end unless objfilter.class == User
    end
    # still not matched? Ignore it
    return nil unless  m[:users] or m[:groups]

    return m
  end

  private :extract_maintainer

  def lookup_package_owner(rootproject, pkg, owner, limit, devel, filter, deepest, already_checked={})
    return nil, limit, already_checked if already_checked[pkg.id]

    # optional check for devel package instance first
    m = nil
    m = extract_maintainer(rootproject, pkg.resolve_devel_package, filter, owner) if devel == true
    m = extract_maintainer(rootproject, pkg, filter, owner) unless m

    already_checked[pkg.id] = 1

    # no match, loop about projects below with this package container name
    unless m
      pkg.project.expand_all_projects.each do |prj|
        p = prj.packages.find_by_name(pkg.name )
        next if p.nil? or already_checked[p.id]
       
        already_checked[p.id] = 1

        m = extract_maintainer(rootproject, p.resolve_devel_package, filter, owner) if devel == true
        m = extract_maintainer(rootproject, p, filter, owner) unless m
        if m
          break unless deepest
        end
      end
    end

    # found entry
    return m, (limit-1), already_checked
  end

  private :lookup_package_owner

  def find_containers_without_definition(rootproject, devel=true, filter=["maintainer","bugowner"] )
    projects=rootproject.expand_all_projects
    roles=[]
    filter.each do |f|
      roles << Role.find_by_title!(f)
    end

    # fast find packages with defintions
    # relationship in package object
    defined_packages = Package.joins(:relationships).where("db_project_id in (?) AND role_id in (?)", projects, roles).pluck(:name)
    # relationship in project object
    Project.joins(:relationships).where("projects.id in (?) AND role_id in (?)", projects, roles).each do |prj|
      defined_packages += prj.packages.map{ |p| p.name }
    end
    if devel == true
      #FIXME add devel packages, but how do recursive lookup fast in SQL?
    end
    defined_packages.uniq!

    all_packages = Package.where("db_project_id in (?)", projects).pluck(:name)
  
    undefined_packages = all_packages - defined_packages 
    maintainers=[]

    undefined_packages.each do |p|
      next if p =~ /\A_product:\w[-+\w\.]*\z/

      pkg = rootproject.find_package(p)
      
      m = {}
      m[:rootproject] = rootproject.name
      m[:project] = pkg.project.name
      m[:package] = pkg.name

      maintainers << m
    end

    return maintainers
  end

  def find_containers(rootproject, owner, devel=true, filter=["maintainer","bugowner"] )
    projects=rootproject.expand_all_projects

    roles=[]
    filter.each do |f|
      roles << Role.find_by_title!(f)
    end

    found_packages = Relationship.where(role_id: roles, package_id: Package.where(:db_project_id => projects).pluck(:id))
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
      maintainers << { :rootproject => rootproject.name, :project => prj }
    end
    Package.where(id: found_packages).each do |pkg|
      maintainers << { :rootproject => rootproject.name, :project => pkg.project.name, :package => pkg.name }
    end

    return maintainers
  end

  def find_assignees(rootproject, binary_name, limit=1, devel=true, filter=["maintainer","bugowner"], webui_mode=false)
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
        m, limit, already_checked = lookup_package_owner(rootproject, pkg, "", limit, devel, filter, deepest, already_checked)

        unless m
          # collect all no matched entries
          m = { :rootproject => rootproject.name, :project => pkg.project.name, :package => pkg.name, :filter => filter }
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

end
