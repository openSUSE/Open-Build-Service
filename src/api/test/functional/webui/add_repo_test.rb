require_relative '../../test_helper'

class Webui::AddRepoTest < Webui::IntegrationTest
  def test_add_default # spec/features/webui/repositories_spec.rb
    use_js
    login_Iggy to: project_show_path(project: 'home:Iggy')

    # actually check there is a link on the project
    click_link 'Repositories'
    page.must_have_text('Repositories of home:Iggy')
    page.must_have_text(/i586, x86_64/)

    click_link 'Add repositories'
    page.must_have_text('Add Repositories to home:Iggy')

    page.must_have_text('KIWI image build')

    find('#submitrepos')['disabled'].must_equal true

    check 'repo_Base_repo'
    check 'repo_images'
    click_button 'Add selected repositories'

    visit project_meta_path(project: 'home:Iggy')
    page.must_have_selector('.editor', visible: false)
    xml = Xmlhash.parse(first('.editor', visible: false).value)
    assert_equal([{"name"=>"images", "arch"=> %w(x86_64 i586) },
                  {"name"=>"Base_repo", "path"=>{"project"=>"BaseDistro2.0", "repository"=>"BaseDistro2_repo"},
                   "arch"=> %w(x86_64 i586) },
                  {"name"=>"10.2", "path"=>{"project"=>"BaseDistro", "repository"=>"BaseDistro_repo"},
                   "arch"=> %w(i586 x86_64) }], xml['repository'])
  end
end
