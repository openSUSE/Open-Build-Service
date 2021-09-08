class Workflow::Step::BranchPackageStep < ::Workflow::Step
  REQUIRED_KEYS = [:source_project, :source_package].freeze
  validates :source_package_name, presence: true

  def call(options = {})
    return unless valid?

    workflow_filters = options.fetch(:workflow_filters, {})

    if scm_webhook.new_pull_request? || scm_webhook.updated_pull_request?
      branch_package(workflow_filters)
    elsif scm_webhook.closed_merged_pull_request?
      destroy_target_project
      delete_subscriptions(target_package)
    elsif scm_webhook.reopened_pull_request?
      restore_target_project
      create_subscriptions(target_package, workflow_filters)
    end
  end

  private

  def branch_package(workflow_filters = {})
    branched_package = find_or_create_branched_package

    add_or_update_branch_request_file(package: branched_package)

    create_or_update_subscriptions(branched_package, workflow_filters)

    workflow_repositories(target_project_name, workflow_filters).each do |repository|
      # TODO: Fix n+1 queries
      workflow_architectures(repository, workflow_filters).each do |architecture|
        # We cannot report multibuild flavors here... so they will be missing from the initial report
        SCMStatusReporter.new({ project: target_project_name, package: target_package_name, repository: repository.name, arch: architecture.name },
                              scm_webhook.payload, @token.scm_token).call
      end
    end

    branched_package
  end

  # Destroy the target project which contains the branched package. It's a soft delete, so it can be restored if needed.
  def destroy_target_project
    # TODO: It's possible that it doesn't work since another step might have already destroyed the project
    Project.find_by(name: target_project_name).destroy
  end

  # Restore the target project which contains the branched package
  def restore_target_project
    # TODO: It's possible that it doesn't work since another step might have already restored the project
    Project.restore(target_project_name)
  end

  def check_source_access
    return if remote_source?

    options = { use_source: false, follow_project_links: true, follow_multibuild: true }

    begin
      src_package = Package.get_by_project_and_name(source_project_name, source_package_name, options)
    rescue Package::UnknownObjectError
      raise BranchPackage::Errors::CanNotBranchPackageNotFound, "Package #{source_project_name}/#{source_package_name} not found, it could not be branched."
    end

    Pundit.authorize(@token.user, src_package, :create_branch?)
  end

  def find_or_create_branched_package
    return target_package if scm_webhook.updated_pull_request? && target_package.present?

    check_source_access

    begin
      BranchPackage.new({ project: source_project_name, package: source_package_name,
                          target_project: target_project_name,
                          target_package: target_package_name }).branch
    rescue BranchPackage::InvalidArgument, InvalidProjectNameError, ArgumentError => e
      raise BranchPackage::Errors::CanNotBranchPackage, "Package #{source_project_name}/#{source_package_name} could not be branched: #{e.message}"
    rescue Project::WritePermissionError, CreateProjectNoPermission => e
      raise BranchPackage::Errors::CanNotBranchPackageNoPermission,
            "Package #{source_project_name}/#{source_package_name} could not be branched due to missing permissions: #{e.message}"
    end

    Event::BranchCommand.create(project: source_project_name, package: source_package_name,
                                targetproject: target_project_name,
                                targetpackage: target_package_name,
                                user: @token.user.login)

    target_package
  end
end
