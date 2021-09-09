class Workflow::Step::LinkPackageStep < ::Workflow::Step
  REQUIRED_KEYS = [:source_project, :source_package].freeze
  validates :source_package_name, presence: true

  def call(options = {})
    return unless valid?

    workflow_filters = options.fetch(:workflow_filters, {})

    case
    when scm_webhook.new_pull_request?
      create_link_package(workflow_filters)
    when scm_webhook.updated_pull_request?
      update_link_package(workflow_filters)
    when scm_webhook.closed_merged_pull_request?
      destroy_target_project
    when scm_webhook.reopened_pull_request?
      restore_target_project(workflow_filters)
    end
  end

  private

  def update_link_package(workflow_filters)
    if target_package.blank?
      create_target_package
      create_subscriptions(target_package, workflow_filters)
    end
    add_or_update_branch_request_file(package: target_package)
    update_subscriptions(target_package, workflow_filters)
    report_to_scm(workflow_filters)
    target_package
  end

  def create_link_package(workflow_filters)
    create_target_package
    create_subscriptions(target_package, workflow_filters)

    add_or_update_branch_request_file(package: target_package)
    report_to_scm(workflow_filters)
    target_package
  end

  def destroy_target_project
    delete_subscriptions(target_package)
    target_project.destroy
  end

  def restore_target_project(workflow_filters)
    Project.restore(target_project_name)
    # we are destroying the subscriptions when a PR is closed
    create_subscriptions(target_package, workflow_filters) if target_package.present?
  end

  def target_project
    Project.find_by(name: target_project_name)
  end

  def create_target_package
    create_project_and_package
    create_special_package
    create_link
  end

  def create_project_and_package
    check_source_access

    raise PackageAlreadyExists, "Can not link package. The package #{target_package_name} already exists." if target_package.present?

    if target_project.nil?
      project = Project.create!(name: target_project_name)
      project.commit_user = User.session
      project.relationships.create!(user: User.session, role: Role.find_by_title('maintainer'))
      project.store
    end

    target_project.packages.create(name: target_package_name)
  end

  # Will raise an exception if the source package is not accesible
  def check_source_access
    return if remote_source?

    Package.get_by_project_and_name(source_project_name, source_package_name)
  end

  # NOTE: the next lines are a temporary fix the allow the service to run in a linked package. A project service is needed.
  def create_special_package
    return if Package.find_by_project_and_name(target_project, '_project')

    special_package = target_project.packages.create(name: '_project')
    special_package.save_file({ file: special_package_file_content, filename: '_service' })
  end

  def special_package_file_content
    <<~XML
      <services>
        <service name="format_spec_file" mode="localonly"/>
      </services>
    XML
  end

  def create_link
    Backend::Api::Sources::Package.write_link(target_project_name,
                                              target_package_name,
                                              @token.user,
                                              link_xml(project: source_project_name, package: source_package_name))

    target_package
  end

  def link_xml(opts = {})
    # "<link package=\"foo\" project=\"bar\" />"
    Nokogiri::XML::Builder.new { |x| x.link(opts) }.doc.root.to_s
  end

  def report_to_scm(workflow_filters)
    workflow_repositories(target_project_name, workflow_filters).each do |repository|
      # TODO: Fix n+1 queries
      workflow_architectures(repository, workflow_filters).each do |architecture|
        # We cannot report multibuild flavors here... so they will be missing from the initial report
        SCMStatusReporter.new({ project: target_project_name, package: target_package_name, repository: repository.name, arch: architecture.name },
                              scm_webhook.payload, @token.scm_token).call
      end
    end
  end
end
