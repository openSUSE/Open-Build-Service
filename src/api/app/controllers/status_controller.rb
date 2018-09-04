require_dependency 'status_helper'

class StatusController < ApplicationController
  def workerstatus
    send_data(WorkerStatus.hidden.to_xml)
  end

  def workercapability
    pass_to_backend(request.path_info)
  end

  def workercommand
    required_parameters :cmd, :project, :package, :repository, :arch

    unless ['checkconstraints'].include?(params[:cmd])
      raise UnknownCommandError, "Unknown command '#{params[:cmd]}' for path #{request.path}"
    end

    # read permission checking
    Package.get_by_project_and_name(params[:project], params[:package])

    path = request.path_info
    path += build_query_from_hash(params, [:cmd, :project, :package, :repository, :arch])
    pass_to_backend(path)
  end

  def history
    required_parameters :hours, :key

    @samples = [params[:samples].to_i, 1].max
    @values = StatusHistory.history_by_key_and_hours(params[:key], params[:hours])
  end

  def project
    dbproj = Project.get_by_name(params[:project])
    @packages = ProjectStatus::Calculator.new(dbproj).calc_status
    find_relationships_for_packages(@packages)
  end

  private

  def role_from_cache(role_id)
    @rolecache[role_id] || (@rolecache[role_id] = Role.find(role_id).title)
  end

  def user_from_cache(user_id)
    @usercache[user_id] || (@usercache[user_id] = User.find(user_id).login)
  end

  def group_from_cache(group_id)
    @groupcache[group_id] || (@groupcache[group_id] = Group.find(group_id).title)
  end

  def find_relationships_for_packages(packages)
    package_hash = {}
    packages.each_value do |p|
      package_hash[p.package_id] = p
      package_hash[p.develpack.package_id] = p.develpack if p.develpack
    end
    @rolecache = {}
    @usercache = {}
    @groupcache = {}
    relationships = Relationship.where(package_id: package_hash.keys).pluck(:package_id, :user_id, :group_id, :role_id)
    relationships.each do |package_id, user_id, group_id, role_id|
      if user_id
        package_hash[package_id].add_person(user_from_cache(user_id),
                                            role_from_cache(role_id))
      else
        package_hash[package_id].add_group(group_from_cache(group_id),
                                           role_from_cache(role_id))
      end
    end
  end
end
