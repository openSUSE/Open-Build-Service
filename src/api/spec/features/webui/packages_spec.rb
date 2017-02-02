require "browser_helper"
require "webmock/rspec"

RSpec.feature "Packages", type: :feature, js: true do
  it_behaves_like 'user tab' do
    let(:package) {
      create(:package, name: "group_test_package",
        project_id: user_tab_user.home_project.id)
    }
    let!(:maintainer_user_role) { create(:relationship, package: package, user: user_tab_user) }
    let(:project_path) { package_show_path(project: user_tab_user.home_project, package: package) }
  end

  let!(:user) { create(:confirmed_user, login: "package_test_user") }
  let!(:package) { create(:package_with_file, name: "test_package", project: user.home_project) }
  let(:other_user) { create(:confirmed_user, login: "other_package_test_user") }
  let!(:other_users_package) { create(:package_with_file, name: "branch_test_package", project: other_user.home_project) }
  let(:package_with_develpackage) { create(:package, name: "develpackage", project: user.home_project, develpackage: other_users_package) }
  let(:third_project) { create(:project_with_package, package_name: "develpackage") }

  describe "branching a package" do
    after do
      # Cleanup backend
      if CONFIG["global_write_through"]
        Suse::Backend.delete("/source/#{CGI.escape(other_user.home_project_name)}")
        Suse::Backend.delete("/source/#{CGI.escape(user.branch_project_name(other_user.home_project_name))}")
      end
    end

    scenario "from another user's project" do
      login user
      visit package_show_path(project: other_user.home_project, package: other_users_package)

      click_link("Branch package")
      click_button("Ok")

      expect(page).to have_text("Successfully branched package")
      expect(page.current_path).to eq(
        package_show_path(project: user.branch_project_name(other_user.home_project_name), package: other_users_package))
    end
  end

  describe "editing package files" do
    let(:file_edit_test_package) { create(:package_with_file, name: "file_edit_test_package", project: user.home_project) }

    before do
      login(user)
      visit package_show_path(project: user.home_project, package: file_edit_test_package)
    end

    scenario "editing an existing file" do
      skip("This started to fail due to js issues in rails 5. Please fix it:-)")
      # somefile.txt is a file of our test package
      click_link("somefile.txt")
      # Workaround to update codemirror text field
      execute_script("$('.CodeMirror')[0].CodeMirror.setValue('added some new text')")
      click_button("Save")

      expect(page).to have_text("The file 'somefile.txt' has been successfully saved.")
      expect(file_edit_test_package.source_file("somefile.txt")).to eq("added some new text")
    end
  end

  scenario "deleting a package" do
    login user
    visit package_show_path(package: package, project: user.home_project)
    click_link("delete-package")
    expect(find("#del_dialog")).to have_text("Do you really want to delete this package?")
    click_button('Ok')
    expect(find("#flash-messages")).to have_text("Package was successfully removed.")
  end

  scenario "requesting package deletion" do
    login user
    visit package_show_path(package: other_users_package, project: other_user.home_project)
    click_link("Request deletion")
    expect(page).to have_text("Do you really want to request the deletion of package ")
    click_button("Ok")
    expect(page).to have_text("Created repository delete request")
    find("a", text: /repository delete request \d+/).click
    expect(page.current_path).to match("/request/show/\\d+")
  end

  scenario "changing the package's devel project" do
    login user
    visit package_show_path(package: package_with_develpackage, project: user.home_project)
    click_link("Request devel project change")
    fill_in "description", with: "Hey, why not?"
    fill_in "devel_project", with: third_project.name
    click_button "Ok"

    expect(find('#flash-messages').text).to be_empty
    request = BsRequest.where(description: "Hey, why not?", creator: user.login, state: "review")
    expect(request).to exist
    expect(page.current_path).to match("/request/show/#{request.first.number}")
    expect(page).to have_text("Created by #{user.login}")
    expect(page).to have_text("In state review")
    expect(page).to have_text("Set the devel project to package #{third_project.name} / develpackage for package #{user.home_project} / develpackage")
  end

  context "triggering package rebuild" do
    let(:repository) { create(:repository, architectures: ["x86_64"]) }
    let(:rebuild_url) {
      "#{CONFIG['source_url']}/build/#{user.home_project.name}?cmd=rebuild&arch=x86_64&package=#{package.name}&repository=#{repository.name}"
    }
    let(:fake_buildresult) {
      "<resultlist state='123'>
         <result project='#{user.home_project.name}' repository='#{repository.name}' arch='x86_64'>
           <binarylist/>
         </result>
       </resultlist>"
    }

    before do
      user.home_project.repositories << repository
      login(user)
      path = "#{CONFIG['source_url']}/build/#{user.home_project}/_result?view=status&package=#{package}&arch=x86_64&repository=#{repository.name}"
      stub_request(:get, path).and_return(body: fake_buildresult)
    end

    scenario "via live build log" do
      visit package_live_build_log_path(project: user.home_project, package: package, repository: repository.name, arch: "x86_64")
      click_link("Trigger Rebuild", match: :first)
      expect(a_request(:post, rebuild_url)).to have_been_made.once
    end

    scenario "via binaries view" do
      allow(Buildresult).to receive(:find_hashed).
        with(project: user.home_project, package: package, repository: repository.name, view: %w(binarylist status)).
        and_return(Xmlhash.parse(fake_buildresult))

      visit package_binaries_path(project: user.home_project, package: package, repository: repository.name)
      click_link("Trigger")
      expect(a_request(:post, rebuild_url)).to have_been_made.once
    end
  end

  context "log" do
    let(:repository) { create(:repository, architectures: ["i586"]) }

    before do
      user.home_project.repositories << repository
      login(user)
      stub_request(:get, "#{CONFIG['source_url']}/build/#{user.home_project}/#{repository.name}/i586/#{package}/_log?nostream=1&start=0&end=65536")
        .and_return(body: '[1] this is my dummy logfile -> ümlaut')
      result = %(<resultlist state="8da2ae1e32481175f43dc30b811ad9b5">
                              <result project="#{user.home_project}" repository="#{repository.name}" arch="i586" code="published" state="published">
                                <status package="#{package}" code="succeeded" />
                              </result>
                            </resultlist>
                            )
      result_path = "#{CONFIG['source_url']}/build/#{user.home_project}/_result?view=status&package=#{package}"
      stub_request(:get, result_path)
        .and_return(body: result)
      stub_request(:get, result_path + "&arch=i586&repository=#{repository.name}")
        .and_return(body: result)
      stub_request(:get, "#{CONFIG['source_url']}/build/#{user.home_project}/#{repository.name}/i586/#{package}/_log")
        .and_return(headers: {'Content-Type'=> 'text/plain'}, body: '[1] this is my dummy logfile -> ümlaut')
    end

    scenario "live build finishes succesfully" do
      visit package_live_build_log_path(project: user.home_project, package: package, repository: repository.name, arch: 'i586')
      expect(page).to have_text('Build finished')
      expect(page).to have_text('[1] this is my dummy logfile -> ümlaut')
    end

    scenario "download logfile succesfully" do
      visit package_show_path(project: user.home_project, package: package)
      # test reload and wait for the build to finish
      find('.icons-reload').click
      find('.buildstatus', 'succeeded').click
      expect(page).to have_text('[1] this is my dummy logfile -> ümlaut')
      first(:link, 'Download logfile').click
      # don't bother with the umlaut
      expect(page.source).to have_text('[1] this is my dummy logfile')
    end
  end
end
