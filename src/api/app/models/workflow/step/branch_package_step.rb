class Workflow::Step::BranchPackageStep < ::Workflow::Step
  REQUIRED_KEYS = [:source_project, :source_package, :target_project].freeze
  validate :validate_source_project_and_package_name

  def call(options = {})
    return unless valid?

    workflow_filters = options.fetch(:workflow_filters, {})
    branch_package(workflow_filters)
  end

  private

  def target_project_base_name
    step_instructions[:target_project]
  end

  def branch_package(workflow_filters = {})
    create_branched_package if scm_webhook.new_pull_request? || (scm_webhook.updated_pull_request? && target_package.blank?) || scm_webhook.push_event? || scm_webhook.tag_push_event?

    add_branch_request_file(package: target_package)

    # SCMs don't support statuses for tags, so we don't need to report back in this case
    create_or_update_subscriptions(target_package, workflow_filters) unless scm_webhook.tag_push_event?

    target_package
  end

  def check_source_access
    return if remote_source?

    options = { use_source: false, follow_project_links: true, follow_multibuild: true }

    begin
      src_package = Package.get_by_project_and_name(source_project_name, source_package_name, options)
    rescue Package::UnknownObjectError
      raise BranchPackage::Errors::CanNotBranchPackageNotFound, "Package #{source_project_name}/#{source_package_name} not found, it could not be branched."
    end

    Pundit.authorize(@token.executor, src_package, :create_branch?)
  end

  def create_branched_package
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
                                user: @token.executor.login)

    target_package
  end
end
