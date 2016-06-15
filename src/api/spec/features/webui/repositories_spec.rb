require "browser_helper"

RSpec.feature "Repositories", :type => :feature, :js => true do
  let!(:user) { create(:confirmed_user) }
  let!(:project) { create(:project) }
  let!(:relationship) { create(:relationship_project_user, project: project, user: user) }

  let!(:my_project) { create(:project, name: 'MyProject') }
  let!(:repository) { create(:repository, name: 'standard', project: my_project) }
  let!(:distribution) { create(:distribution, project: 'MyProject', repository: 'standard') }

  scenario "add" do
    login user
    visit "/project/add_repository_from_default_list/#{project.name}"

    check "repo_#{distribution.reponame}"
    click_button 'Add selected repositories'

    expect(page).to have_text("Successfully added repositories")
    expect(page).to have_css("div.repository-container", text: distribution.reponame)
  end
end
