# Everything that needs to be done before you can use this app

require 'fileutils'
require 'yaml'
require 'tasks/dev/helper_methods'

namespace :dev do
  task :prepare do
    puts 'Setting up the database configuration...'
    copy_example_file('config/database.yml')
    database_yml = YAML.load_file('config/database.yml') || {}
    database_yml['test']['host'] = 'db'
    database_yml['development']['host'] = 'db'
    database_yml['production']['host'] = 'db'
    File.write('config/database.yml', YAML.dump(database_yml))

    puts 'Setting up the application configuration...'
    copy_example_file('config/options.yml')
    puts 'Copying thinking sphinx example...'
    copy_example_file('config/thinking_sphinx.yml')

    puts 'Setting up the cloud uploader'
    copy_example_file('../../dist/aws_credentials')
    copy_example_file('../../dist/ec2utils.conf')
  end

  desc 'Bootstrap the application'
  task :bootstrap, [:old_test_suite] => [:prepare, :environment] do |_t, args|
    args.with_defaults(old_test_suite: false)

    puts 'Creating the database...'
    begin
      Rake::Task['db:version'].invoke
    rescue StandardError
      Rake::Task['db:setup'].invoke
      if args.old_test_suite
        puts 'Old test suite. Loading fixtures...'
        Rake::Task['db:fixtures:load'].invoke
      end
    end

    if Rails.env.test?
      puts 'Prepare assets'
      Rake::Task['assets:clobber'].invoke
      Rake::Task['assets:precompile'].invoke
      if args.old_test_suite
        puts 'Old test suite. Enforcing project keys...'
        ::Configuration.update(enforce_project_keys: true)
      end
    end

    if Rails.env.development?
      # This is needed to make the signer setup
      puts 'Configure default signing'
      Rake::Task['assets:clobber'].invoke
      ::Configuration.update(enforce_project_keys: true)
    end

    puts 'Enable feature toggles for their group'
    Rake::Task['flipper:enable_features_for_group'].invoke
  end

  # This is automatically run in Review App or manually in development env.
  namespace :development_testdata do
    desc 'Creates test data to play with in dev and CI environments'
    task create: :environment do
      unless Rails.env.development?
        puts "You are running this rake task in #{Rails.env} environment."
        puts 'Please only run this task with RAILS_ENV=development'
        puts 'otherwise it will destroy your database data.'
        return
      end
      require 'factory_bot'
      include FactoryBot::Syntax::Methods
      require 'active_support/testing/time_helpers'
      include ActiveSupport::Testing::TimeHelpers

      Rails.cache.clear
      Rake::Task['db:reset'].invoke

      puts 'Enable feature toggles for their group'
      Rake::Task['flipper:enable_features_for_group'].invoke

      iggy = create(:staff_user, login: 'Iggy')
      admin = User.get_default_admin
      User.session = admin

      interconnect = create(:remote_project, name: 'openSUSE.org', remoteurl: 'https://api.opensuse.org/public')
      # The interconnect doesn't work unless we set the distributions
      FetchRemoteDistributionsJob.perform_now
      tw_repository = create(:repository, name: 'snapshot', project: interconnect, remote_project_name: 'openSUSE:Factory')

      # the home:Admin is not created because the Admin user is created in seeds.rb
      # therefore we need to create it manually and also set the proper relationship
      home_admin = create(:project, name: admin.home_project_name)
      create(:relationship, project: home_admin, user: admin, role: Role.hashed['maintainer'])
      admin_repository = create(:repository, project: home_admin, name: 'openSUSE_Tumbleweed', architectures: ['x86_64'])
      create(:path_element, link: tw_repository, repository: admin_repository)
      ruby_admin = create(:package_with_file, name: 'ruby', project: home_admin, file_content: 'from admin home')

      branches_iggy = create(:project, name: iggy.branch_project_name('home:Admin'))
      ruby_iggy = create(:package_with_file, name: 'ruby', project: branches_iggy, file_content: 'from iggies branch')
      create(
        :bs_request_with_submit_action,
        creator: iggy,
        target_project: home_admin,
        target_package: ruby_admin,
        source_project: branches_iggy,
        source_package: ruby_iggy
      )

      test_package = create(:package, name: 'hello_world', project: home_admin)
      backend_url = "/source/#{CGI.escape(home_admin.name)}/#{CGI.escape(test_package.name)}"
      Backend::Connection.put("#{backend_url}/hello_world.spec", File.read('../../dist/t/spec/fixtures/hello_world.spec'))

      leap = create(:project, name: 'openSUSE:Leap:15.0')
      leap_apache = create(:package_with_file, name: 'apache2', project: leap)
      leap_repository = create(:repository, project: leap, name: 'openSUSE_Tumbleweed', architectures: ['x86_64'])
      create(:path_element, link: tw_repository, repository: leap_repository)

      # we need to set the user again because some factories set the user back to nil :(
      User.session = admin
      update_project = create(:update_project, target_project: leap, name: "#{leap.name}:Update")
      create(
        :maintenance_project,
        name: 'MaintenanceProject',
        title: 'official maintenance space',
        target_project: update_project,
        maintainer: admin
      )

      # Create factory dashboard projects
      factory = create(:project, name: 'openSUSE:Factory')
      sworkflow = create(:staging_workflow, project: factory)
      checker = create(:confirmed_user, login: 'repo-checker')
      create(:relationship, project: factory, user: checker, role: Role.hashed['reviewer'])
      osrt = create(:group, title: 'review-team')
      reviewhero = create(:confirmed_user, login: 'reviewhero')
      osrt.users << reviewhero
      osrt.save
      create(:relationship, project: factory, group: osrt, role: Role.hashed['reviewer'])
      tw_apache = create(:package_with_file, name: 'apache2', project: factory)

      req = travel_to(90.minutes.ago) do
        new_package1 = create(
          :bs_request_with_submit_action,
          creator: iggy,
          target_package: 'inreview',
          target_project: factory,
          source_package: leap_apache
        )
        new_package1.staging_project = sworkflow.staging_projects.first
        new_package1.reviews << create(:review, by_project: new_package1.staging_project)
        new_package1.save
        new_package1.change_review_state(:accepted, by_group: sworkflow.managers_group.title)

        new_package2 = create(
          :bs_request_with_submit_action,
          creator: iggy,
          target_package: 'reviewed',
          target_project: factory,
          source_package: leap_apache
        )
        new_package2.staging_project = sworkflow.staging_projects.second
        new_package2.reviews << create(:review, by_project: new_package2.staging_project)
        new_package2.save
        new_package2.change_review_state(:accepted, by_group: sworkflow.managers_group.title)
        new_package2.change_review_state(:accepted, by_user: checker.login)
        new_package2.change_review_state(:accepted, by_group: osrt.title)
        new_package2.change_review_state(:accepted, by_package: 'apache2', by_project: leap.name)

        req = create(
          :bs_request_with_submit_action,
          creator: iggy,
          target_package: tw_apache,
          source_package: leap_apache,
          review_by_user: checker
        )
        User.session = iggy
        req.reviews.create(by_group: osrt.title)
        req
      end

      travel_to(88.minutes.ago) do
        User.session = checker
        req.change_review_state(:accepted, by_user: checker.login, comment: 'passed')
      end

      travel_to(20.minutes.ago) do
        # accepting last review - new state
        User.session = reviewhero
        req.change_review_state(:accepted, by_group: osrt.title, comment: 'looks good')
      end

      comment = travel_to(85.minutes.ago) do
        create(:comment, commentable: req)
      end
      create(:comment, commentable: req, parent: comment)

      User.session = iggy
      req.addreview(by_user: admin.login, comment: 'is this really fine?')

      create(:project, name: 'openSUSE:Factory:Rings:0-Bootstrap')
      create(:project, name: 'openSUSE:Factory:Rings:1-MinimalX')

      Configuration.download_url = 'https://download.opensuse.org'
      Configuration.save

      # Other special projects and packages
      create(:project, name: 'linked_project', link_to: home_admin)
      create(:multibuild_package, project: home_admin, name: 'multibuild_package')
      create(:package_with_link, project: home_admin, name: 'linked_package')
      create(:package_with_remote_link, project: home_admin, name: 'remotely_linked_package', remote_project_name: 'openSUSE.org:openSUSE:Factory', remote_package_name: 'aaa_base')

      # Trigger package builds for home:Admin
      home_admin.store

      # Create notifications by running the `dev:notifications:data` task two times
      Rake::Task['dev:notifications:data'].invoke(2)

      # Create a workflow token, some workflow runs and their related data
      Rake::Task['workflows:create_workflow_runs'].invoke

      # Create a request with multiple actions
      Rake::Task['requests:multiple_actions_request'].invoke
    end
  end
end
