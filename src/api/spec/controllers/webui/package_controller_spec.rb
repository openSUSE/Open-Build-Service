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
    RSpec.shared_examples "a response of a successful submit request" do
      it { expect(flash[:notice]).to match("Created .+submit request \\d.+to .+#{target_project}") }
      it { expect(response).to redirect_to(package_show_path(project: source_project, package: package)) }
      it { expect(BsRequestActionSubmit.where(target_project: target_project.name, target_package: package.name)).to exist }
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

    context "having whitespaces in parameters" do
      before do
        post :submit_request, params: { project: " #{source_project} ", package: " #{package} ", targetproject: " #{target_project} " }
      end

      it_should_behave_like "a response of a successful submit request"
    end

    context 'not successful' do
      before do
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
  end

  describe 'POST #save' do
    before do
      login(user)
      post :save, params: {
          project: source_project, package: source_package, title: 'New title for package', description: 'New description for package'
        }
    end

    it { expect(flash[:notice]).to eq("Package data for '#{source_package.name}' was saved successfully") }
    it { expect(source_package.reload.title).to eq('New title for package') }
    it { expect(source_package.reload.description).to eq('New description for package') }
    it { expect(response).to redirect_to(package_show_path(project: source_project, package: source_package)) }
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
    before do
      login(user)
    end

    context "without any uploaded file data" do
      it "fails with an error message" do
        post :save_file, params: { project: source_project, package: source_package }
        expect(response).to redirect_to(root_path)
        expect(flash[:error]).to eq("Error while creating '' file: No file or URI given.")
      end
    end

    context "with an invalid filename" do
      it "fails with a backend error message" do
        post :save_file, params: { project: source_project, package: source_package, filename: ".test" }
        expect(response).to redirect_to(root_path)
        expect(flash[:error]).to eq("Error while creating '.test' file: filename '.test' is illegal.")
      end
    end

    context "adding a file that doesn't exist yet" do
      before do
        post :save_file, params: { project: source_project, package: source_package, filename: "newly_created_file", file_type: "local" }
      end

      it { expect(response).to have_http_status(:found) }
      it { expect(flash[:success]).to eq("The file 'newly_created_file' has been successfully saved.") }
      it { expect(source_package.source_file("newly_created_file")).to be nil }
    end

    context "uploading a utf-8 file" do
      let(:file_to_upload) { File.read(File.expand_path(Rails.root.join("spec/support/files/chinese.txt"))) }

      before do
        post :save_file, params: { project: source_project, package: source_package, filename: "学习总结", file: file_to_upload }
      end

      it { expect(response).to have_http_status(:found) }
      it { expect(flash[:success]).to eq("The file '学习总结' has been successfully saved.") }
      it "creates the file" do
        expect { source_package.source_file("学习总结") }.not_to raise_error
        expect(URI.encode(source_package.source_file("学习总结"))).to eq(URI.encode(file_to_upload))
      end
    end

    context "uploading a file from remote URL" do
      before do
        post :save_file, params: {
            project: source_project, package: source_package, filename: "remote_file",
            file_url: "https://raw.github.com/openSUSE/open-build-service/master/.gitignore"
          }
      end

      it { expect(response).to have_http_status(:found) }
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

    context "uploading a valid special file (_aggregate)" do
      let(:file_to_upload) { File.read(File.expand_path(Rails.root.join("test/texts/aggregate.xml"))) }

      before do
        post :save_file, params: { project: source_project, package: source_package, file: file_to_upload, filename: "_aggregate" }
      end

      it { expect(response).to have_http_status(:found) }
      it { expect(flash[:success]).to eq("The file '_aggregate' has been successfully saved.") }

      it "create the '_aggregate' file" do
        expect { source_package.source_file("_aggregate") }.not_to raise_error
        expect(URI.encode(source_package.source_file("_aggregate"))).to eq(URI.encode(file_to_upload))
      end
    end

    context "uploading an invalid special file (_link)" do
      before do
        post :save_file, params: {
            project: source_project, package: source_package, filename: "_link",
            file: File.expand_path(Rails.root.join("test/texts/broken_link.xml"))
          }
      end

      it { expect(response).to have_http_status(:found) }
      it { expect(flash[:error]).to eq("Error while creating '_link' file: link validation error: Start tag expected, '<' not found.") }
      it "does not create a '_link' file" do
        expect { source_package.source_file("_link") }.to raise_error ActiveXML::Transport::NotFoundError
      end
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

    context "with a package that have derived packages" do
      before do
        login user
        BranchPackage.new(project: source_project.name, package: package.name).branch
        get :show, params: { project: source_project, package: package }
      end

      it { expect(assigns(:linking_packages)).to match_array(package.linking_packages) }
    end

    context 'with a package that has a broken service' do
      before do
        login user
        get :show, params: { project: user.home_project, package: broken_service_package.name }
      end

      it { expect(flash[:error]).to include('Files could not be expanded:') }
      it { expect(assigns(:more_info)).to include('service daemon error:') }
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
    before do
      login(user)
    end

    context "without source access" do
      before do
        package.add_flag("sourceaccess", "disable")
        package.save!
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
        # This is necessary to delete the commits created in the before statement
        package.destroy
      end

      it { expect(assigns(:project)).to eq(source_project) }
      it { expect(assigns(:package)).to eq(package) }

      context "with no revisions" do
        it { expect(assigns(:lastrev)).to eq(1) }
        it { expect(assigns(:revisions)).to eq([1]) }
      end

      context "with less than 21 revisions" do
        let(:package_with_commits) { create(:package_with_file, name: "package_with_commits", project: source_project) }

        before do
          19.times { |i| Suse::Backend.put("/source/#{source_project}/#{package_with_commits}/somefile.txt", i.to_s) }
          get :revisions, params: { project: source_project, package: package_with_commits }
        end

        after do
          # This is necessary to delete the commits created in the before statement
          package_with_commits.destroy
        end

        it { expect(assigns(:lastrev)).to eq(20) }
        it { expect(assigns(:revisions)).to eq((1..20).to_a.reverse) }
      end

      context "with 21 revisions" do
        let(:package_with_more_commits) { create(:package_with_file, name: "package_with_more_commits", project: source_project) }

        before do
          20.times { |i| Suse::Backend.put("/source/#{source_project}/#{package_with_more_commits}/somefile.txt", i.to_s) }
          get :revisions, params: { project: source_project, package: package_with_more_commits }
        end

        after do
          # This is necessary to delete the commits created in the before statement
          package_with_more_commits.destroy
        end

        it { expect(assigns(:lastrev)).to eq(21) }
        it { expect(assigns(:revisions)).to eq((2..21).to_a.reverse) }

        context "with showall parameter set" do
          before do
            get :revisions, params: { project: source_project, package: package_with_more_commits, showall: true }
          end

          it { expect(assigns(:revisions)).to eq((1..21).to_a.reverse) }
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
      let(:post_url) { "#{CONFIG['source_url']}/source/#{source_project}/#{source_package}?cmd=runservice&user=#{user}" }

      before do
        get :trigger_services, params: { project: source_project, package: source_package }
      end

      it { expect(a_request(:post, post_url)).to have_been_made.once }
      it { expect(flash[:error]).to eq("Services couldn't be triggered: no source service defined!") }
      it { is_expected.to redirect_to(action: :show, project: source_project, package: source_package) }
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
        expect(flash[:error]).to eq('Error while saving the Meta file: package validation error: ' +
                                    'Opening and ending tag mismatch: package line 1 and paaaaackage.')
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
    RSpec.shared_examples "build log" do
      context "successfully" do
        before do
          path = "#{CONFIG['source_url']}/build/#{user.home_project}/_result?view=status" \
                 "&package=#{source_package}&arch=i586&repository=10.2"
          stub_request(:get, path).and_return(body:
            %(<resultlist state='123'>
               <result project='#{user.home_project.name}' repository='10.2' arch='i586'>
                 <binarylist/>
               </result>
              </resultlist>))
          do_request project: source_project, package: source_package, repository: '10.2', arch: 'i586', format: 'js'
        end

        it { expect(response).to have_http_status(:ok) }
      end

      context "with a protected package" do
        let!(:flag) { create(:sourceaccess_flag, project: source_project) }

        before do
          do_request project: source_project, package: source_package, repository: '10.2', arch: 'i586', format: 'js'
        end

        it { expect(flash[:error]).to eq('Could not access build log') }
        it { expect(response).to redirect_to(package_show_path(project: source_project, package: source_package)) }
      end

      context "with a non existant package" do
        before do
          do_request project: source_project, package: 'nonexistant', repository: '10.2', arch: 'i586'
        end

        it { expect(flash[:error]).to eq("Couldn't find package 'nonexistant' in project '#{source_project}'. Are you sure it exists?") }
        it { expect(response).to redirect_to(project_show_path(project: source_project)) }
      end

      context "with a non existant project" do
        before do
          do_request project: 'home:foo', package: 'nonexistant', repository: '10.2', arch: 'i586'
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
    end

    describe "GET #update_build_log" do
      def do_request(params)
        get :update_build_log, params: params, xhr: true
      end

      it_should_behave_like "build log"
    end
  end
end
