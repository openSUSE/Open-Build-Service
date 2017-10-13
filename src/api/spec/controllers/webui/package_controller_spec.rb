require "webmock/rspec"
require 'rails_helper'
# WARNING: If you change owner tests make sure you uncomment this line
# and start a test backend. Some of the Owner methods
# require real backend answers for projects/packages.
# CONFIG['global_write_through'] = true

RSpec.describe Webui::PackageController, vcr: true do
  let(:admin) { create(:admin_user, login: "admin") }
  let(:user) { create(:confirmed_user, login: 'tom') }
  let(:source_project) { user.home_project }
  let(:source_package) { create(:package, name: 'my_package', project: source_project) }
  let(:target_project) { create(:project) }
  let(:package) { create(:package_with_file, name: "package_with_file", project: source_project) }
  let(:service_package) { create(:package_with_service, name: "package_with_service", project: source_project) }
  let(:broken_service_package) { create(:package_with_broken_service, name: "package_with_broken_service", project: source_project) }
  let(:repo_for_source_project) do
    repo = create(:repository, project: source_project, architectures: ['i586'])
    source_project.store
    repo
  end
  let(:fake_build_results) do
    Buildresult.new(
      '<resultlist state="2b71f05ecb8742e3cd7f6066a5097c72">
        <result project="home:tom" repository="fake_repo_name" arch="i586" code="unknown" state="unknown" dirty="true">
         <binarylist>
            <binary filename="fake_binary_001"/>
            <binary filename="fake_binary_002"/>
            <binary filename="updateinfo.xml"/>
            <binary filename="rpmlint.log"/>
          </binarylist>
        </result>
      </resultlist>')
  end
  let(:fake_build_results_without_binaries) do
    Buildresult.new(
      '<resultlist state="2b71f05ecb8742e3cd7f6066a5097c72">
        <result project="home:tom" repository="fake_repo_name" arch="i586" code="unknown" state="unknown" dirty="true">
         <binarylist>
          </binarylist>
        </result>
      </resultlist>')
  end

  describe "POST #submit_request" do
    let(:target_package) { package.name }

    RSpec.shared_examples "a response of a successful submit request" do
      it { expect(flash[:notice]).to match("Created .+submit request \\d.+to .+#{target_project}") }
      it { expect(response).to redirect_to(package_show_path(project: source_project, package: package)) }
      it { expect(BsRequestActionSubmit.where(target_project: target_project.name, target_package: target_package)).to exist }
    end

    before do
      login(user)
    end

    context "sending a valid submit request" do
      before do
        post :submit_request, params: { project: source_project, package: package, targetproject: target_project }
      end

      it_should_behave_like "a response of a successful submit request"
    end

    context "sending a valid submit request with targetpackage as parameter" do
      let(:target_package) { 'different_package' }

      before do
        post :submit_request, params: { project: source_project, package: package, targetproject: target_project, targetpackage: target_package }
      end

      it_should_behave_like "a response of a successful submit request"
    end

    context "sending a valid submit request with 'sourceupdate' parameter" do
      before do
        post :submit_request, params: { project: source_project, package: package, targetproject: target_project, sourceupdate: 'update' }
      end

      it_should_behave_like "a response of a successful submit request"

      it 'creates a submit request with correct sourceupdate attibute' do
        created_request = BsRequestActionSubmit.where(target_project: target_project.name, target_package: target_package).first
        expect(created_request.sourceupdate).to eq('update')
      end
    end

    context 'superseeding a request that does not exist' do
      before do
        post :submit_request, params: { project: source_project, package: package, targetproject: target_project, supersede_request_numbers: [42] }
      end

      it { expect(flash[:notice]).to match(" Superseding failed: Couldn't find request with id '42'") }
      it_should_behave_like "a response of a successful submit request"
    end

    context "having whitespaces in parameters" do
      before do
        post :submit_request, params: { project: " #{source_project} ", package: " #{package} ", targetproject: " #{target_project} " }
      end

      it_should_behave_like "a response of a successful submit request"
    end

    context 'sending a submit request for an older submission' do
      before do
        3.times { |i| Backend::Connection.put("/source/#{source_project}/#{package}/somefile.txt", i.to_s) }
        post :submit_request, params: { project: source_project, package: package, targetproject: target_project, rev: 2 }
      end

      it_should_behave_like "a response of a successful submit request"

      it 'creates a submit request for the correct revision' do
        expect(BsRequestActionSubmit.where(
                 source_project: source_project.name,
                 source_package: package.name,
                 target_project: target_project.name,
                 target_package: package.name,
                 type:           'submit',
                 source_rev:     2
        )).to exist
      end
    end

    context 'not successful' do
      before do
        # NOTE: This test has to run with running backend, but 'global_write_through' disabled
        stub_const('CONFIG', CONFIG.merge({ 'global_write_through' => false }))
        post :submit_request, params: { project: source_project, package: source_package, targetproject: target_project.name }
      end

      it { expect(flash[:error]).to eq('Unable to submit: The source of package home:tom/my_package is broken') }
      it { expect(response).to redirect_to(package_show_path(project: source_project, package: source_package)) }
      it { expect(BsRequestActionSubmit.where(target_project: target_project.name, target_package: source_package.name)).not_to exist }
    end

    context "a submit request that fails due to validation errors" do
      let(:unconfirmed_user) { create(:user) }

      before do
        login(unconfirmed_user)
        post :submit_request, params: { project: source_project, package: package, targetproject: target_project }
      end

      it { expect(flash[:error]).to eq("Unable to submit: Validation failed: Creator Login #{unconfirmed_user.login} is not an active user") }
      it { expect(response).to redirect_to(package_show_path(project: source_project, package: package)) }
      it { expect(BsRequestActionSubmit.where(target_project: target_project.name, target_package: package.name)).not_to exist }
    end

    context "unchanged sources" do
      before do
        post :submit_request, params: { project: source_project, package: package, targetproject: source_project }
      end

      it { expect(flash[:error]).to eq("Unable to submit, sources are unchanged") }
      it { expect(response).to redirect_to(package_show_path(project: source_project, package: package)) }
      it { expect(BsRequestActionSubmit.where(target_project: source_project.name, target_package: package.name)).not_to exist }
    end

    context "invalid request (missing parameters)" do
      before do
        post :submit_request, params: { project: source_project, package: "", targetproject: source_project }
      end

      it { expect(flash[:error]).to eq("Unable to submit: #{source_project}/") }
      it { expect(response).to redirect_to(project_show_path(project: source_project)) }
      it { expect(BsRequestActionSubmit.where(target_project: source_project.name)).not_to exist }
    end

    context "sending a submit request without target" do
      before do
        post :submit_request, params: { project: 'unknown', package: package, targetproject: target_project, targetpackage: target_package }
      end

      it 'creates a submit request with correct sourceupdate attibute' do
        expect(flash[:error]).to eq("Unable to submit (missing target): unknown")
      end

      it { expect(response).to redirect_to(root_path) }
      it { expect(BsRequestActionSubmit.where(target_project: target_project, target_package: target_package)).not_to exist }
    end
  end

  describe 'POST #save' do
    before do
      login(user)
    end

    context 'valid data' do
      before do
        post :save, params: {
            project: source_project, package: source_package, title: 'New title for package', description: 'New description for package'
          }
      end

      it { expect(flash[:notice]).to eq("Package data for '#{source_package.name}' was saved successfully") }
      it { expect(source_package.reload.title).to eq('New title for package') }
      it { expect(source_package.reload.description).to eq('New description for package') }
      it { expect(response).to redirect_to(package_show_path(project: source_project, package: source_package)) }
    end

    context 'invalid data' do
      before do
        post :save, params: {
            project: source_project, package: source_package, title: 'New title for package', description: SecureRandom.hex(32768) # = 65536 chars
          }
      end

      it { expect(controller).to set_flash[:error] }
      it { expect(response).to redirect_to(package_edit_path(project: source_project, package: source_package)) }
    end
  end

  describe "GET #meta" do
    before do
      get :meta, params: { project: source_project, package: source_package }
    end

    it 'sends the xml representation of a package' do
      expect(assigns(:meta)).to eq(source_package.render_xml)
    end
    it { expect(response).to render_template("package/meta") }
    it { expect(response).to have_http_status(:success) }
  end

  describe "POST #branch" do
    before do
      login(user)
    end

    it "shows an error if source package does not exist" do
      post :branch, params: { linked_project: source_project, linked_package: "does_not_exist" }
      expect(flash[:error]).to eq("Failed to branch: Package does not exist.")
      expect(response).to redirect_to(root_path)
    end

    it "shows an error if source package parameter not provided" do
      post :branch, params: { linked_project: source_project }
      expect(flash[:error]).to eq("Failed to branch: Linked Package parameter missing")
      expect(response).to redirect_to(root_path)
    end

    it "shows an error if source project does not exist" do
      post :branch, params: { linked_project: "does_not_exist", linked_package: source_package }
      expect(flash[:error]).to eq("Failed to branch: Package does not exist.")
      expect(response).to redirect_to(root_path)
    end

    it "shows an error if user has no permissions for source project" do
      post :branch, params: { linked_project: source_project, linked_package: source_package, target_project: 'home:admin:nope' }
      expect(flash[:error]).to eq("Sorry, you are not authorized to create this Project.")
      expect(response).to redirect_to(root_path)
    end

    it "shows an error if source project parameter not provided" do
      post :branch, params: { linked_package: source_package }
      expect(flash[:error]).to eq("Failed to branch: Linked Project parameter missing")
      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST #remove" do
    before do
      login(user)
    end

    describe "authentification" do
      let(:target_package) { create(:package, name: "forbidden_package", project: target_project) }

      it "does not allow other users than the owner to delete a package" do
        post :remove, params: { project: target_project, package: target_package }

        expect(flash[:error]).to eq("Sorry, you are not authorized to delete this Package.")
        expect(target_project.packages).not_to be_empty
      end

      it "allows admins to delete other user's packages" do
        login(admin)
        post :remove, params: { project: target_project, package: target_package }

        expect(flash[:notice]).to eq("Package was successfully removed.")
        expect(target_project.packages).to be_empty
      end
    end

    context "a package" do
      before do
        post :remove, params: { project: user.home_project, package: source_package }
      end

      it { expect(response).to have_http_status(:found) }
      it { expect(flash[:notice]).to eq("Package was successfully removed.") }
      it "deletes the package" do
        expect(user.home_project.packages).to be_empty
      end
    end

    context "a package with dependencies" do
      let(:devel_project) { create(:package, project: target_project) }

      before do
        source_package.develpackages << devel_project
      end

      it "does not delete the package and shows an error message" do
        post :remove, params: { project: user.home_project, package: source_package }

        expect(flash[:notice]).to eq "Package can't be removed: used as devel package by #{target_project}/#{devel_project}"
        expect(user.home_project.packages).not_to be_empty
      end

      context "forcing the deletion" do
        before do
          post :remove, params: { project: user.home_project, package: source_package, force: true }
        end

        it "deletes the package" do
          expect(flash[:notice]).to eq "Package was successfully removed."
          expect(user.home_project.packages).to be_empty
        end
      end
    end
  end

  describe 'GET #binaries' do
    before do
      login user
    end

    after do
      Package.destroy_all
      Repository.destroy_all
    end

    context 'with a failure in the backend' do
      before do
        allow(Buildresult).to receive(:find_hashed).and_raise(ActiveXML::Transport::Error, 'fake message')
        post :binaries, params: { package: source_package, project: source_project, repository: repo_for_source_project }
      end

      it { expect(flash[:error]).to eq('fake message') }
      it { expect(response).to redirect_to(package_show_path(project: source_project, package: source_package)) }
    end

    context 'without build results' do
      before do
        allow(Buildresult).to receive(:find_hashed)
        post :binaries, params: { package: source_package, project: source_project, repository: repo_for_source_project }
      end

      it { expect(flash[:error]).to eq("Package \"#{source_package}\" has no build result for repository #{repo_for_source_project.to_param}") }
      it { expect(response).to redirect_to(package_show_path(project: source_project, package: source_package, nextstatus: 404)) }
    end

    context 'with build results and no binaries' do
      render_views

      before do
        allow(Buildresult).to receive(:find).and_return(fake_build_results_without_binaries)
        post :binaries, params: { package: source_package, project: source_project, repository: repo_for_source_project }
      end

      it { expect(response).to have_http_status(:success) }
      it { expect(response.body).to match(/No built binaries/) }
    end

    context 'with build results and binaries' do
      render_views

      before do
        allow(Buildresult).to receive(:find).and_return(fake_build_results)
        post :binaries, params: { package: source_package, project: source_project, repository: repo_for_source_project }
      end

      it { expect(response).to have_http_status(:success) }
      it { expect(response.body).to match(/fake_binary_001/) }
      it { expect(response.body).to match(/fake_binary_002/) }
      it { expect(response.body).to match(/updateinfo.xml/) }
      it { expect(response.body).to match(/rpmlint.log/) }
    end
  end

  describe "POST #save_file" do
    RSpec.shared_examples 'tests for save_file action' do
      before do
        login(user)
      end

      context "without any uploaded file data" do
        it "fails with an error message" do
          do_request(project: source_project, package: source_package)
          expect(response).to expected_failure_response
          expect(flash[:error]).to eq("Error while creating '' file: No file or URI given.")
        end
      end

      context "with an invalid filename" do
        it "fails with a backend error message" do
          do_request(project: source_project, package: source_package, filename: ".test")
          expect(response).to expected_failure_response
          expect(flash[:error]).to eq("Error while creating '.test' file: '.test' is not a valid filename.")
        end
      end

      context "adding a file that doesn't exist yet" do
        before do
          do_request(
            project:   source_project,
            package:   source_package,
            filename:  "newly_created_file",
            file_type: "local",
            file: "some_content"
          )
        end

        it { expect(response).to have_http_status(expected_success_status) }
        it { expect(flash[:success]).to eq("The file 'newly_created_file' has been successfully saved.") }
        it { expect(source_package.source_file("newly_created_file")).to eq('some_content') }
      end

      context "uploading a utf-8 file" do
        let(:file_to_upload) { File.read(File.expand_path(Rails.root.join("spec/support/files/chinese.txt"))) }

        before do
          do_request(project: source_project, package: source_package, filename: "学习总结", file: file_to_upload)
        end

        it { expect(response).to have_http_status(expected_success_status) }
        it { expect(flash[:success]).to eq("The file '学习总结' has been successfully saved.") }
        it "creates the file" do
          expect { source_package.source_file("学习总结") }.not_to raise_error
          expect(URI.encode(source_package.source_file("学习总结"))).to eq(URI.encode(file_to_upload))
        end
      end

      context "uploading a file from remote URL" do
        before do
          do_request(
            project: source_project, package: source_package, filename: "remote_file",
            file_url: "https://raw.github.com/openSUSE/open-build-service/master/.gitignore"
          )
        end

        after do
          # Make sure the service only once get's created
          source_package.destroy
        end

        it { expect(response).to have_http_status(expected_success_status) }
        it { expect(flash[:success]).to eq("The file 'remote_file' has been successfully saved.") }
        # Uploading a remote file creates a service instead of downloading it directly!
        it "creates a valid service file" do
          expect { source_package.source_file("_service") }.not_to raise_error
          expect { source_package.source_file("remote_file") }.to raise_error ActiveXML::Transport::NotFoundError

          created_service = source_package.source_file("_service")
          expect(created_service).to eq(<<-EOT.strip)
<services>
  <service name="download_url">
    <param name="host">raw.github.com</param>
    <param name="protocol">https</param>
    <param name="path">/openSUSE/open-build-service/master/.gitignore</param>
    <param name="filename">remote_file</param>
  </service>
</services>
EOT
        end
      end
    end

    context "as ajax request" do
      let(:expected_success_status) { :ok }
      let(:expected_failure_response) { have_http_status(:bad_request) }

      def do_request(params)
        post :save_file, xhr: true, params: params
      end

      include_examples 'tests for save_file action'
    end

    context "as non-ajax request" do
      let(:expected_success_status) { :found }
      let(:expected_failure_response) { redirect_to(root_path) }

      def do_request(params)
        post :save_file, params: params
      end

      include_examples 'tests for save_file action'
    end
  end

  describe "GET #show" do
    context "require_package before_action" do
      context "with an invalid package" do
        before do
          get :show, params: { project: user.home_project, package: 'no_package' }
        end

        it "returns 302 status" do
          expect(response.status).to eq(302)
        end

        it "redirects to project show path" do
          expect(response).to redirect_to(project_show_path(project: user.home_project, nextstatus: 404))
        end

        it "shows error flash message" do
          expect(flash[:error]).to eq("Package \"no_package\" not found in project \"#{user.home_project}\"")
        end
      end
    end

    context "with a valid package" do
      before do
        get :show, params: { project: user.home_project, package: source_package.name }
      end

      it "assigns @package" do
        expect(assigns(:package)).to eq(source_package)
      end
    end

    context 'with a package that has a broken service' do
      before do
        login user
        get :show, params: { project: user.home_project, package: broken_service_package.name }
      end

      it { expect(flash[:error]).to include('Files could not be expanded:') }
      it { expect(assigns(:more_info)).to include('service daemon error:') }
    end

    context 'revision handling' do
      let(:package_with_revisions) do
        create(:package_with_revisions, name: 'rev_package', revision_count: 3, project: user.home_project)
      end

      after do
        # Cleanup: otherwhise older revisions stay in backend and influence other tests, and test re-runs
        package_with_revisions.destroy
      end

      context "with a 'rev' parameter with existent revision" do
        before do
          get :show, params: { project: user.home_project, package: package_with_revisions, rev: 2 }
        end

        it { expect(assigns(:revision)).to eq('2') }
        it { expect(response).to have_http_status(:success) }
      end

      context "with a 'rev' parameter with non-existent revision" do
        before do
          get :show, params: { project: user.home_project, package: package_with_revisions, rev: 4 }
        end

        it { expect(flash[:error]).to eq('No such revision: 4') }
        it { expect(response).to redirect_to(package_show_path(project: user.home_project, package: package_with_revisions)) }
      end
    end
  end

  describe "DELETE #remove_file" do
    before do
      login(user)
      allow_any_instance_of(Package).to receive(:delete_file).and_return(true)
    end

    def remove_file_post
      post :remove_file, params: { project: user.home_project, package: source_package, filename: 'the_file' }
    end

    context "with successful backend call" do
      before do
        remove_file_post
      end

      it { expect(flash[:notice]).to eq("File 'the_file' removed successfully") }
      it { expect(assigns(:package)).to eq(source_package) }
      it { expect(assigns(:project)).to eq(user.home_project) }
      it { expect(response).to redirect_to(package_show_path(project: user.home_project, package: source_package)) }
    end

    context "with not successful backend call" do
      before do
        allow_any_instance_of(Package).to receive(:delete_file).and_raise(ActiveXML::Transport::NotFoundError)
        remove_file_post
      end

      it { expect(flash[:notice]).to eq("Failed to remove file 'the_file'") }
    end

    context "without filename parameter" do
      it "renders 404" do
        post :remove_file, params: { project: user.home_project, package: source_package }
        expect(response.status).to eq(404)
      end
    end

    it "calls delete_file method" do
      allow_any_instance_of(Package).to receive(:delete_file).with('the_file')
      remove_file_post
    end
  end

  describe "GET #revisions" do
    let(:package) { create(:package_with_revisions, name: 'package_with_one_revision', revision_count: 1, project: source_project) }

    before do
      login(user)
    end

    context "without source access" do
      before do
        package.add_flag("sourceaccess", "disable")
        package.save
        get :revisions, params: { project: source_project, package: package }
      end

      it { expect(flash[:error]).to eq("Could not access revisions") }
      it { expect(response).to redirect_to(package_show_path(project: source_project.name, package: package.name)) }
    end

    context "with source access" do
      before do
        get :revisions, params: { project: source_project, package: package }
      end

      after do
        # Delete revisions that got created in the backend
        package.destroy
      end

      it { expect(assigns(:project)).to eq(source_project) }
      it { expect(assigns(:package)).to eq(package) }

      context "with no revisions" do
        it { expect(assigns(:lastrev)).to eq(1) }
        it { expect(assigns(:revisions)).to eq([1]) }
      end

      context "with less than 21 revisions" do
        let(:package_with_commits) { create(:package_with_revisions, name: 'package_with_20_revisions', revision_count: 20, project: source_project) }

        before do
          get :revisions, params: { project: source_project, package: package_with_commits }
        end

        after do
          # Delete revisions that got created in the backend
          package_with_commits.destroy
        end

        it { expect(assigns(:lastrev)).to eq(20) }
        it { expect(assigns(:revisions)).to eq((1..20).to_a.reverse) }
      end

      context "with 21 revisions" do
        let(:package_with_more_commits) {
          create(:package_with_revisions, name: 'package_with_21_revisions', revision_count: 21, project: source_project)
        }

        before do
          get :revisions, params: { project: source_project, package: package_with_more_commits }
        end

        after do
          # Delete revisions that got created in the backend
          package_with_more_commits.destroy
        end

        it { expect(assigns(:lastrev)).to eq(21) }

        it 'lists the last 20 revisions' do
          expect(assigns(:revisions)).to eq((2..21).to_a.reverse)
        end

        context "with showall parameter set" do
          before do
            get :revisions, params: { project: source_project, package: package_with_more_commits, showall: true }
          end

          it 'lists all revisions' do
            expect(assigns(:revisions)).to eq((1..21).to_a.reverse)
          end
        end
      end
    end
  end

  describe 'GET #trigger_services' do
    before do
      login user
    end

    context 'with right params' do
      let(:post_url) { "#{CONFIG['source_url']}/source/#{source_project}/#{service_package}?cmd=runservice&user=#{user}" }

      before do
        get :trigger_services, params: { project: source_project, package: service_package }
      end

      it { expect(a_request(:post, post_url)).to have_been_made.once }
      it { expect(flash[:notice]).to eq('Services successfully triggered') }
      it { is_expected.to redirect_to(action: :show, project: source_project, package: service_package) }
    end

    context "without a service file in the package" do
      let(:package) { create(:package_with_file, name: "package_with_file", project: source_project) }
      let(:post_url) { "#{CONFIG['source_url']}/source/#{source_project}/#{package}?cmd=runservice&user=#{user}" }

      before do
        get :trigger_services, params: { project: source_project, package: package }
      end

      it { expect(a_request(:post, post_url)).to have_been_made.once }
      it { expect(flash[:error]).to eq("Services couldn't be triggered: no source service defined!") }
      it { is_expected.to redirect_to(action: :show, project: source_project, package: package) }
    end
  end

  describe "POST #save_meta" do
    let(:valid_meta) do
      "<package name=\"#{source_package.name}\" project=\"#{source_project.name}\">" +
      "<title>My Test package Updated via Webui</title><description/></package>"
    end

    let(:invalid_meta_because_package_name) do
      "<package name=\"whatever\" project=\"#{source_project.name}\">" +
      "<title>Invalid meta PACKAGE NAME</title><description/></package>"
    end

    let(:invalid_meta_because_project_name) do
      "<package name=\"#{source_package.name}\" project=\"whatever\">" +
      "<title>Invalid meta PROJECT NAME</title><description/></package>"
    end

    let(:invalid_meta_because_xml) do
      "<package name=\"#{source_package.name}\" project=\"#{source_project.name}\">" +
      "<title>Invalid meta WRONG XML</title><description/></paaaaackage>"
    end

    before do
      login user
    end

    context "with proper params" do
      before do
        post :save_meta, params: { project: source_project, package: source_package, meta: valid_meta }
      end

      it { expect(flash[:success]).to eq("The Meta file has been successfully saved.") }
      it { expect(response).to have_http_status(:ok) }
    end

    context "with an invalid package name" do
      before do
        post :save_meta, params: { project: source_project, package: source_package, meta: invalid_meta_because_package_name }
      end

      it { expect(flash[:error]).to eq('Error while saving the Meta file: package name in xml data does not match resource path component.') }
      it { expect(response).to have_http_status(:bad_request) }
    end

    context "with an invalid project name" do
      before do
        post :save_meta, params: { project: source_project, package: source_package, meta: invalid_meta_because_project_name }
      end

      it { expect(flash[:error]).to eq("Error while saving the Meta file: project name in xml data does not match resource path component.") }
      it { expect(response).to have_http_status(:bad_request) }
    end

    context "with invalid XML" do
      before do
        post :save_meta, params: { project: source_project, package: source_package, meta: invalid_meta_because_xml }
      end

      it do
        expect(flash[:error]).to match(/Error while saving the Meta file: package validation error.*FATAL:/)
        expect(flash[:error]).to match(/Opening and ending tag mismatch: package line 1 and paaaaackage\./)
      end
      it { expect(response).to have_http_status(:bad_request) }
    end

    context "with an unexistent package" do
      before do
        post :save_meta, params: { project: source_project, package: 'blah', meta: valid_meta }
      end

      it { expect(flash[:error]).to eq("Error while saving the Meta file: Package doesn't exists in that project..") }
      it { expect(response).to have_http_status(:bad_request) }
    end
  end

  describe 'GET #rdiff' do
    context "when no difference in sources diff is empty" do
      before do
        get :rdiff, params: { project: source_project, package: package, oproject: source_project, opackage: package }
      end

      it { expect(assigns[:filenames]).to be_empty }
    end

    context "when an empty revision is provided" do
      before do
        get :rdiff, params: { project: source_project, package: package, rev: '' }
      end

      it { expect(flash[:error]).to eq('Error getting diff: revision is empty') }
      it { is_expected.to redirect_to(package_show_path(project: source_project, package: package)) }
    end
  end

  context "build logs" do
    let(:source_project_with_plus) { create(:project, name: 'foo++bar') }
    let(:package_of_project_with_plus) { create(:package, name: 'some_package', project: source_project_with_plus) }
    let(:source_package_with_plus) { create(:package, name: 'my_package++special', project: source_project) }
    let(:repo_leap_42_2) { create(:repository, name: 'leap_42.2', project: source_project, architectures: ['i586']) }
    let(:architecture) { repo_leap_42_2.architectures.first }

    RSpec.shared_examples "build log" do
      before do
        login user
        repo_leap_42_2
        source_project.store
      end

      context "successfully" do
        before do
          path = "#{CONFIG['source_url']}/build/#{user.home_project}/_result?arch=i586" \
                 "&package=#{source_package}&repository=#{repo_leap_42_2}&view=status"
          stub_request(:get, path).and_return(body:
            %(<resultlist state='123'>
               <result project='#{user.home_project}' repository='#{repo_leap_42_2}' arch='i586'>
                 <binarylist/>
               </result>
              </resultlist>))
          do_request project: source_project, package: source_package, repository: repo_leap_42_2.name, arch: 'i586', format: 'js'
        end

        it { expect(response).to have_http_status(:ok) }
      end

      context "successfully with a package which name that includes '+'" do
        before do
          path = "#{CONFIG['source_url']}/build/#{user.home_project}/_result?arch=i586" \
                 "&package=#{source_package_with_plus}&repository=#{repo_leap_42_2}&view=status"
          stub_request(:get, path).and_return(body:
            %(<resultlist state='123'>
               <result project='#{user.home_project}' repository='#{repo_leap_42_2}' arch='i586'>
                 <binarylist/>
               </result>
              </resultlist>))
          do_request project: source_project, package: source_package_with_plus, repository: repo_leap_42_2.name, arch: 'i586', format: 'js'
        end

        it { expect(response).to have_http_status(:ok) }
      end

      context "successfully with a project which name that includes '+'" do
        let(:repo_leap_45_1) { create(:repository, name: 'leap_45.1', project: source_project_with_plus, architectures: ['i586']) }

        before do
          repo_leap_45_1
          source_project_with_plus.store

          path = "#{CONFIG['source_url']}/build/#{source_project_with_plus}/_result?arch=i586" \
                 "&package=#{package_of_project_with_plus}&repository=#{repo_leap_45_1}&view=status"
          stub_request(:get, path).and_return(body:
            %(<resultlist state='123'>
               <result project='#{source_project_with_plus}' repository='#{repo_leap_45_1}' arch='i586'>
                 <binarylist/>
               </result>
              </resultlist>))
          do_request project: source_project_with_plus, package: package_of_project_with_plus,
            repository: repo_leap_45_1.name, arch: 'i586', format: 'js'
        end

        it { expect(response).to have_http_status(:ok) }
      end

      context "with a protected package" do
        let!(:flag) { create(:sourceaccess_flag, project: source_project) }

        before do
          do_request project: source_project, package: source_package, repository: repo_leap_42_2.name, arch: 'i586', format: 'js'
        end

        it { expect(flash[:error]).to eq('Could not access build log') }
        it { expect(response).to redirect_to(package_show_path(project: source_project, package: source_package)) }
      end

      context "with a non existant package" do
        before do
          do_request project: source_project, package: 'nonexistant', repository: repo_leap_42_2.name, arch: 'i586'
        end

        it { expect(flash[:error]).to eq("Couldn't find package 'nonexistant' in project '#{source_project}'. Are you sure it exists?") }
        it { expect(response).to redirect_to(project_show_path(project: source_project)) }
      end

      context "with a non existant project" do
        before do
          do_request project: 'home:foo', package: 'nonexistant', repository: repo_leap_42_2.name, arch: 'i586'
        end

        it { expect(flash[:error]).to eq("Couldn't find project 'home:foo'. Are you sure it still exists?") }
        it { expect(response).to redirect_to(root_path) }
      end
    end

    describe 'GET #package_live_build_log' do
      def do_request(params)
        get :live_build_log, params: params
      end

      it_should_behave_like "build log"

      context "with a nonexistant repository" do
        before do
          do_request project: source_project, package: source_package, repository: 'nonrepository', arch: 'i586'
        end

        it { expect(flash[:error]).not_to be_nil }
        it { expect(response).to redirect_to(package_show_path(source_project, source_package)) }
      end

      context "with a nonexistant architecture" do
        before do
          do_request project: source_project, package: source_package, repository: repo_leap_42_2.name, arch: 'i566'
        end

        it { expect(flash[:error]).not_to be_nil }
        it { expect(response).to redirect_to(package_show_path(source_project, source_package)) }
      end

      context "with a multibuild package" do
        let(:params) {
          { project:    source_project,
            package:    "#{source_package}:multibuild-package",
            repository: repo_leap_42_2.name,
            arch:       architecture.name}
        }
        let(:starttime) { 1.hour.ago.to_i }

        before do
          path = "#{CONFIG['source_url']}/build/#{source_project}/_result?arch=i586" \
                 "&package=#{source_package}:multibuild-package&repository=#{repo_leap_42_2}&view=status"
          stub_request(:get, path).and_return(body: %(<resultlist state='123'>
               <result project='#{source_project}' repository='#{repo_leap_42_2}' arch='i586' code="unpublished" state="unpublished">
                <status package="#{source_package}:multibuild-package" code="succeeded" />
               </result>
              </resultlist>))

          path = "#{CONFIG['source_url']}/build/#{source_project}/#{repo_leap_42_2}/i586/_builddepinfo" \
                  "?package=#{source_package}:multibuild-package&view=revpkgnames"
          stub_request(:get, path).and_return(body: %(<builddepinfo>
                <package name="#{source_package}:multibuild-package">
                <source>apache2</source>
                <pkgdep>apache2</pkgdep>
                </package>
              </builddepinfo>))

          Timecop.freeze(Time.now) do
            path = "#{CONFIG['source_url']}/build/#{source_project}/#{repo_leap_42_2}/i586/#{source_package}:multibuild-package/_jobstatus"
            body = "<jobstatus workerid='42' starttime='#{starttime}'/>"
            stub_request(:get, path).and_return(body: body)

            do_request params
          end
        end

        it { expect(assigns(:what_depends_on)).to eq(['apache2']) }
        it { expect(assigns(:status)).to eq('succeeded') }
        it { expect(assigns(:workerid)).to eq('42') }
        it { expect(assigns(:buildtime)).to eq(1.hour.to_i) }
      end
    end

    describe "GET #update_build_log" do
      def do_request(params)
        get :update_build_log, params: params, xhr: true
      end

      it_should_behave_like "build log"

      context "with a nonexistant repository" do
        before do
          do_request project: source_project, package: source_package, repository: 'nonrepository', arch: 'i586'
        end

        it { expect(assigns(:errors)).not_to be_nil }
        it { expect(response).to have_http_status(:ok) }
      end

      context "with a nonexistant architecture" do
        before do
          do_request project: source_project, package: source_package, repository: repo_leap_42_2.name, arch: 'i566'
        end

        it { expect(assigns(:errors)).not_to be_nil }
        it { expect(response).to have_http_status(:ok) }
      end

      context 'for multibuild package' do
        let(:params) {
          { project:    source_project,
            package:    "#{source_package}:multibuild-package",
            repository: repo_leap_42_2.name,
            arch:       architecture.name}
        }

        before do
          path = "#{CONFIG['source_url']}/build/#{source_project}/#{repo_leap_42_2}/i586/#{source_package}:multibuild-package/_log?view=entry"
          body = "<directory><entry name=\"_log\" size=\"#{32 * 1024}\" mtime=\"1492267770\" /></directory>"
          stub_request(:get, path).and_return(body: body)
          do_request params
        end

        it { expect(assigns(:log_chunk)).not_to be_nil }
        it { expect(assigns(:package)).to eq("#{source_package}:multibuild-package") }
        it { expect(assigns(:project)).to eq(source_project) }
        it { expect(assigns(:offset)).to eq(0) }
      end
    end
  end

  describe 'POST #trigger_rebuild' do
    before do
      login(user)
    end

    context 'when triggering a rebuild fails' do
      before do
        post :trigger_rebuild, params: { project: source_project, package: source_package }
      end

      it 'lets the user know there was an error' do
        expect(flash[:error]).to match("Error while triggering rebuild for home:tom/my_package")
      end

      it 'redirects to the package binaries path' do
        expect(response).to redirect_to(
          controller: :package,
          action: :binaries,
          project: source_project,
          package: source_package
        )
      end
    end

    context 'when triggering a rebuild succeeds' do
      before do
        create(:repository, project: source_project, architectures: ['i586'])
        source_project.store

        post :trigger_rebuild, params: { project: source_project, package: source_package }
      end

      it { expect(flash[:notice]).to eq("Triggered rebuild for #{source_project.name}/#{source_package.name} successfully.") }
      it { expect(response).to redirect_to(package_show_path(project: source_project, package: source_package)) }
    end
  end

  describe 'POST #wipe_binaries' do
    before do
      login(user)
    end

    context 'when wiping binaries fails' do
      before do
        post :wipe_binaries, params: { project: source_project, package: source_package }
      end

      it 'lets the user know there was an error' do
        expect(flash[:error]).to match("Error while triggering wipe binaries for home:tom/my_package")
        expect(flash[:error]).to match("no repository defined")
      end
      it { expect(response).to redirect_to(package_binaries_path(project: source_project, package: source_package)) }
    end

    context 'when wiping binaries succeeds' do
      before do
        create(:repository, project: source_project, architectures: ['i586'])
        source_project.store

        post :wipe_binaries, params: { project: source_project, package: source_package }
      end

      it { expect(flash[:notice]).to eq("Triggered wipe binaries for #{source_project.name}/#{source_package.name} successfully.") }
      it { expect(response).to redirect_to(package_binaries_path(project: source_project, package: source_package)) }
    end
  end

  describe 'POST #abort_build' do
    before do
      login(user)
    end

    context 'when aborting the build fails' do
      before do
        post :abort_build, params: { project: source_project, package: source_package, repository: 'foo', arch: 'bar' }
      end

      it 'lets the user know there was an error' do
        expect(flash[:error]).to match("Error while triggering abort build for home:tom/my_package")
        expect(flash[:error]).to match("no repository defined")
      end
      it {
        expect(response).to redirect_to(package_live_build_log_path(
                                          project: source_project, package: source_package, repository: 'foo', arch: 'bar'))
      }
    end

    context 'when aborting the build succeeds' do
      before do
        create(:repository, project: source_project, architectures: ['i586'])
        source_project.store

        post :abort_build, params: { project: source_project, package: source_package }
      end

      it { expect(flash[:notice]).to eq("Triggered abort build for #{source_project.name}/#{source_package.name} successfully.") }
      it { expect(response).to redirect_to(package_show_path(project: source_project, package: source_package)) }
    end
  end

  describe 'GET #statistics' do
    let!(:repository) { create(:repository, name: 'statistics', project: source_project, architectures: ['i586']) }

    before do
      login(user)

      # Save the repository in backend
      source_project.store
    end

    context 'when backend returns statistics' do
      before do
        allow(Statistic).to receive(:find_hashed).
          with(project: source_project, package: source_package, repository: repository.name, arch: 'i586').
          and_return({ disk: { usage: 20, size: 30 } })

        get :statistics, params: { project: source_project, package: source_package, arch: 'i586', repository: repository.name }
      end

      it { expect(assigns(:statistics)).to eq({ disk: { usage: 20, size: 30 } }) }
      it { expect(response).to have_http_status(:success) }
    end

    context 'when backend does not return statistics' do
      before do
        get :statistics, params: { project: source_project, package: source_package, arch: 'i586', repository: repository.name }
      end

      it { expect(flash[:error]).to eq("No statistics of a successful build could be found in #{repository}/i586") }
      it {
        expect(response).to redirect_to(package_binaries_path(
                                          project: source_project, package: source_package, repository: repository.name, nextstatus: 404))
      }
    end

    context 'when backend raises an exception' do
      before do
        allow(Statistic).to receive(:find_hashed).
          with(project: source_project, package: source_package, repository: repository.name, arch: 'i586').
          and_raise(ActiveXML::Transport::ForbiddenError)

        get :statistics, params: { project: source_project, package: source_package, arch: 'i586', repository: repository.name }
      end

      it { expect(flash[:error]).to eq("No statistics of a successful build could be found in #{repository}/i586") }
      it {
        expect(response).to redirect_to(package_binaries_path(
                                          project: source_project, package: source_package, repository: repository.name, nextstatus: 404))
      }
    end
  end

  describe '#rpmlint_result' do
    let(:fake_build_result) {
      Buildresult.new(
        '
        <resultlist state="eb0459ee3b000176bb3944a67b7c44fa">
          <result project="home:tom" repository="openSUSE_Tumbleweed" arch="i586" code="building" state="building">
            <status package="my_package" code="excluded" />
          </result>
          <result project="home:tom" repository="openSUSE_Leap_42.1" arch="armv7l" code="unknown" state="unknown" />
          <result project="home:tom" repository="openSUSE_Leap_42.1" arch="x86_64" code="building" state="building">
            <status package="my_package" code="signing" />
          </result>
          <result project="home:tom" repository="images" arch="x86_64" code="building" state="building">
            <status package="my_package" code="signing" />
          </result>
        </resultlist>
        '
      )
    }

    before do
      allow(Buildresult).to receive(:find).and_return(fake_build_result)
      post :rpmlint_result, xhr: true, params: { package: source_package, project: source_project }
    end

    it { expect(response).to have_http_status(:success) }
    it { expect(assigns(:repo_list)).to include(['openSUSE_Leap_42.1', 'openSUSE_Leap_42_1']) }
    it { expect(assigns(:repo_list)).not_to include(%w[images images]) }
    it { expect(assigns(:repo_list)).not_to include(%w[openSUSE_Tumbleweed openSUSE_Tumbleweed]) }
    it { expect(assigns(:repo_arch_hash)['openSUSE_Leap_42_1']).to include('x86_64') }
    it { expect(assigns(:repo_arch_hash)['openSUSE_Leap_42_1']).not_to include('armv7l') }
  end

  describe 'GET #submit_request_dialog' do
    let(:package) { create(:package_with_changes_file, project: source_project, name: 'package_with_changes_file') }

    before do
      login(user)
      get :submit_request_dialog,
          xhr: true,
          params: { project: source_project, package: package, targetpackage: source_package, targetproject: source_project }
    end

    it { expect(assigns(:package)).to eq(package) }
    it { expect(assigns(:project)).to eq(source_project) }
    it { expect(assigns(:tpkg)).to eq(source_package.name) }
    it { expect(assigns(:tprj)).to eq(source_project.name) }
    it { expect(assigns(:description)).to eq("- Testing the submit diff\n- Temporary hack") }
  end
end
