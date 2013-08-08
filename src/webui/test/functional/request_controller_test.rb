require File.expand_path(File.dirname(__FILE__) + "/..") + "/test_helper"

class RequestControllerTest < ActionDispatch::IntegrationTest

  def test_my_involved_requests
    login_Iggy
    visit "/home/requests?user=king"

    page.must_have_selector "table#request_table tr"

    # walk over the table
    rs = find('tr#tr_request_997_1').find('.request_target')
    rs.find(:xpath, '//a[@title="kde4"]').must_have_text "kde4"
    rs.find(:xpath, '//a[@title="kdelibs"]').must_have_text "kdelibs"
  end

  test "can request role addition for projects" do
    login_Iggy
    visit project_show_path(project: "home:tom")
    click_link "Request role addition"
    find(:id, "role").select("Bugowner")
    fill_in "description", with: "I can fix bugs too."
    click_button "Ok"
    # request created
    page.must_have_text "Iggy Pop (Iggy) wants the role bugowner for project home:tom"
    find("#description_text").must_have_text "I can fix bugs too."
    page.must_have_selector("input[@name='revoked']")
    page.must_have_text("In state new")

    logout
    login_tom
    visit "/request/show/1001"
    page.must_have_text "Iggy Pop (Iggy) wants the role bugowner for project home:tom"
    click_button "Accept"
  end

  test "can request role addition for packages" do
    login_Iggy
    visit package_show_path(project: "home:Iggy", package: "TestPack")
    # no need for "request role"
    page.wont_have_link "Request role addition"
    # foreign package
    visit package_show_path(project: "Apache", package: "apache2")
    click_link "Request role addition"
    find(:id, "role").select("Maintainer")
    fill_in "description", with: "I can fix bugs too."
    click_button "Ok"
    # request created
    find("#action_display_0").must_have_text "Iggy Pop (Iggy) wants the role maintainer for package Apache / apache2"
    find("#description_text").must_have_text "I can fix bugs too."
    page.must_have_selector("input[@name='revoked']")
    page.must_have_text("In state new")


    logout
    login_tom
    visit request_show_path(1001)
    find("#action_display_0").must_have_text "Iggy Pop (Iggy) wants the role maintainer for package Apache / apache2"
    # tom is not apache maintainer
    page.wont_have_button "Accept"

    logout
    login_fred
    visit "/request/show/1001"
    find("#action_display_0").must_have_text "Iggy Pop (Iggy) wants the role maintainer for package Apache / apache2"
    click_button "Accept"

    # now check the role addition link is gone
    logout
    login_Iggy
    visit package_show_path(project: "Apache", package: "apache2")
    page.wont_have_link "Request role addition"

  end

  test "invalid id gives error" do
    login_Iggy
    visit request_show_path(2000)
    page.must_have_text("Can't find request 2000")
    page.must_have_text("Requests for Iggy")
  end

  test "submit package and revoke" do
    login_Iggy
    visit package_show_path(project: 'home:Iggy', package: 'TestPack')
    click_link "Submit package"
    fill_in "targetproject", with: "home:tom"
    fill_in "description", with: "Want it?"
    click_button "Ok"

    page.must_have_text "Created submit request 1001 to home:tom"
    click_link "submit request 1001"

    # request view shows diff
    page.must_have_text "+Group: Group/Subgroup"

    # tab
    page.must_have_text "My Decision"
    fill_in "reason", with: "Great work!"
    # TODO: the button should not be there at all
    click_button 'accept_request_button'
    page.must_have_text 'No permission to modify target of request 1001'

    fill_in "reason", with: "Oops"
    click_button "Revoke request"

    page.must_have_text "Request revoked!"
    page.must_have_text "Request 1001 (revoked)"
    page.must_have_text "There's nothing to be done right now"
  end

  test "tom adds reviewer Iggy" do
    login_tom
    visit home_path

    within("tr#tr_request_1000_1") do
      page.must_have_text "~:kde4 / BranchPack"
      first(:css, "a.request_link").click
    end

    page.must_have_text "Review for tom"
    click_link "My Decision"
    click_link "Add a review"

    page.must_have_text "Add Reviewer"
    fill_in "review_user", with: "Iggy"
    click_button "Ok"

    page.must_have_text "Request 1000 (review)"
    page.must_have_text "Open review for Iggy"

    logout
    login_Iggy
    visit request_show_path(1000)
    page.must_have_text "Review for Iggy"
    fill_in "review_comment_0", with: "BranchPack sounds strange"
    click_button "Decline review"
    page.must_have_text "Request 1000 (declined)"
  end

  test "request 1000 can expand" do
    # no login required
    visit request_show_path(1000)
    within "#diff_headline_myfile_diff_action_0_submit_0_0" do
      page.wont_have_text "+DummyContent"
      click_link "[+]"
      page.wont_have_text "[+]"
      page.must_have_text "[-]"
    end

    # diff is expanded
    page.must_have_text "+DummyContent"
  end

  test "comment creation without login" do
    logout
    visit "/request/comments/1000"
    find_button("Add comment").click
    find('#flash-messages').must_have_text "Please login to access the requested page."
  end
end
