# -*- coding: utf-8 -*-
require_relative '../../test_helper'

class Webui::PackageControllerTest < Webui::IntegrationTest

  include Webui::WebuiHelper

  def delete_and_recreate_kdelibs
    delete_package 'kde4', 'kdelibs'

    # now we need to recreate it again to avoid teardown to leave a mess in backend/API
    find(:link, 'Create package').click
    fill_in 'name', with: 'kdelibs'
    fill_in 'title', with: 'blub' # see the fixtures!!
    find_button('Save changes').click
    page.must_have_selector '#delete-package'
  end

  def test_show_package_binary_as_user
    login_user('fred', 'geröllheimer', to:
        package_binaries_path(package: 'TestPack', project: 'home:Iggy', repository: '10.2'))

    find(:link, 'Show').click
    page.must_have_text 'Maximal used disk space: 1005 Mbyte'
    page.must_have_text 'Maximal used memory: 288 Mbyte'
    page.must_have_text 'Total build: 503 s'
  end

  def test_show_invalid_package
    visit package_show_path(package: 'TestPok', project: 'home:Iggy')
    page.status_code.must_equal 404
  end

  def test_show_invalid_project
    visit package_show_path(package: 'TestPok', project: 'home:Oggy')
    page.status_code.must_equal 404
  end

  uses_transaction :test_delete_package_as_user
  def test_delete_package_as_user
    use_js

    login_user('fred', 'geröllheimer')
    delete_and_recreate_kdelibs
  end

  uses_transaction :test_delete_package_as_admin
  def test_delete_package_as_admin
    use_js

    login_king
    delete_and_recreate_kdelibs
  end


  def test_Iggy_adds_himself_as_reviewer
    use_js

    login_Iggy to: package_users_path(package: 'TestPack', project: 'home:Iggy')
    check('user_reviewer_Iggy')
    # wait for it to be clickable again before switching pages
    page.wont_have_xpath('.//input[@id="user_reviewer_Iggy"][@disabled="disabled"]')
    click_link 'Advanced'
    click_link 'Meta'
    page.must_have_text '<person userid="Iggy" role="reviewer"/>'
  end

  def test_Iggy_removes_himself_as_bugowner
    use_js

    login_Iggy to: package_meta_path(package: 'TestPack', project: 'home:Iggy')
    page.must_have_text '<person userid="Iggy" role="bugowner"/>'
    within '#package_tabs' do
      click_link('Users')
    end
    uncheck('user_bugowner_Iggy')
    # wait for it to be clickable again before switching pages
    page.wont_have_xpath './/input[@id="user_bugowner_Iggy"][@disabled="disabled"]'
    click_link 'Advanced'
    click_link 'Meta'
    page.wont_have_text '<person userid="Iggy" role="bugowner"/>'
  end

  def fill_comment(body = 'Comment Body')
    fill_in 'body', with: body
    find_button('Add comment').click
    find('#flash-messages').must_have_text 'Comment was successfully created.'
  end

  def test_succesful_comment_creation
    use_js
    login_Iggy
    visit root_path + '/package/show/home:Iggy/TestPack'
    # rubocop:disable Metrics/LineLength
    fill_comment "Write some http://link.com\n\nand some other\n\n* Markdown\n* markup\n\nReferencing sr#23, bco#24, fate#25, @_nobody_, @a-dashed-user and @Iggy. https://anotherlink.com"
    # rubocop:enable Metrics/LineLength
    within('div.thread_level_0') do
      page.must_have_link "http://link.com"
      page.must_have_xpath '//ul//li[text()="Markdown"]'
      page.must_have_xpath '//p[text()="and some other"]'
      page.must_have_xpath '//a[contains(@href, "/request/show/23") and text()="sr#23"]'
      page.must_have_xpath '//a[@href="http://bugzilla.clutter-project.org/show_bug.cgi?id=24" and text()="bco#24"]'
      page.must_have_xpath '//a[@href="https://features.opensuse.org/25" and text()="fate#25"]'
      page.must_have_link '@nobody'
      page.must_have_link '@a-dashed-user'
      page.must_have_link '@Iggy'
      page.must_have_xpath '//a[@href="http://link.com"]'
      page.must_have_xpath '//a[@href="https://anotherlink.com"]'
    end
  end

  def test_another_succesful_comment_creation
    use_js
    login_Iggy
    visit root_path + '/package/show?project=home:Iggy&package=TestPack'
    # @Iggy works at the very beginning and requests are case insensitive
    fill_comment "@Iggy likes to mention himself and to write request#23 with capital 'R', like Request#23."
    within('div.thread_level_0') do
      page.must_have_xpath '//a[contains(@href, "/request/show/23") and text()="request#23"]'
      page.must_have_xpath '//a[contains(@href, "/request/show/23") and text()="Request#23"]'
      page.must_have_link '@Iggy'
    end
  end

# broken test: issue 408
# test "check comments on remote projects" do
#   login_Iggy
#   visit package_show_path(project: "UseRemoteInstanceIndirect", package: "patchinfo")
#   fill_comment
# end

  def test_succesful_reply_comment_creation
    use_js
    login_Iggy
    visit root_path + '/package/show/BaseDistro3/pack2'

    find(:id, 'reply_link_id_201').click
    fill_in 'reply_body_201', with: 'Comment Body'
    find(:id, 'add_reply_201').click
    find('#flash-messages').must_have_text 'Comment was successfully created.'
  end

  def test_diff_is_empty
    visit '/package/rdiff/BaseDistro2.0/pack2.linked?opackage=pack2&oproject=BaseDistro2.0'
    find('#content').must_have_text 'No source changes!'
  end

  def test_revision_is_empty
    visit '/package/rdiff/BaseDistro2.0/pack2.linked?opackage=pack2&oproject=BaseDistro2.0&rev='
    flash_message_type.must_equal :alert
    flash_message.must_equal 'Error getting diff: revision is empty'
  end

  def test_group_can_modify
    use_js

    # verify we do not test ghosts
    login_adrian to: package_users_path(package: 'TestPack', project: 'home:Iggy')

    page.wont_have_link 'Add group'
    logout

    login_Iggy to: package_users_path(package: 'TestPack', project: 'home:Iggy')
    click_link 'Add group'
    page.must_have_text 'Add New Group to TestPack'
    fill_in 'groupid', with: 'test_group'
    click_button 'Add group'
    flash_message.must_equal 'Added group test_group with role maintainer'
    within('#group_table_wrapper') do
      page.must_have_link 'test_group'
    end
    logout

    # now test adrian can modify it for real
    login_adrian to: package_users_path(package: 'TestPack', project: 'home:Iggy')
    page.must_have_link 'Add group'
  end

  def test_derived_packages
    use_js

    login_adrian to: package_show_path(package: 'pack2', project: 'BaseDistro')
    page.must_have_text '1 derived packages'
    click_link 'derived packages'

    page.must_have_text 'Derived Packages'
    page.must_have_link 'BaseDistro:Update'
  end

  def test_download_logfile
    use_js

    visit package_show_path(package: 'TestPack', project: 'home:Iggy')
    # test reload and wait for the build to finish
    starttime=Time.now
    while Time.now - starttime < 10
      reload_button = first('.icons-reload')
      if !reload_button
        sleep 0.1
        next
      end
      reload_button.click
      if page.has_selector? '.buildstatus'
        break if first('.buildstatus').text == 'succeeded'
      end
    end
    first('.buildstatus').must_have_text 'succeeded'
    click_link 'succeeded'
    find(:id, 'log_space').must_have_text '[1] this is my dummy logfile -&gt; ümlaut'
    first(:link, 'Download logfile').click
    # don't bother with the ümlaut
    assert_match %r{this is my dummy}, page.source
  end

  def test_delete_request
    use_js

    login_tom to: package_show_path(package: 'TestPack', project: 'home:Iggy')
    click_link 'Request deletion'

    fill_in 'description', with: 'It was just a test'
    click_button 'Ok'

    page.must_have_text 'Delete package home:Iggy / TestPack'
    click_button 'Revoke request'
  end

  def test_change_devel_request
    use_js

    # we need a package with current devel package
    login_tom to: package_show_path(package: 'kdelibs', project: 'kde4')
    click_link 'Request devel project change'

    page.must_have_content 'Do you want to request to change the devel project for package kde4 / kdelibs from project home:coolo:test'
    fill_in 'description', with: 'It was just a test'
    fill_in 'devel_project', with: 'home:coolo:test' # not really a change, but the package is reset
    click_button 'Ok'

    find('#flash-messages').must_have_text 'No such package: home:coolo:test/kdelibs'
    # check that no harm was done
    assert_equal packages(:home_coolo_test_kdelibs_DEVEL_package), packages(:kde4_kdelibs).develpackage
  end

  uses_transaction :test_submit_package

  def test_submit_package
    use_js

    login_adrian to: project_show_path(project: 'home:adrian')
    click_link 'Branch existing package'
    fill_in 'linked_project', with: 'home:dmayr'
    fill_in 'linked_package', with: 'x11vnc'
    click_button 'Create Branch'

    page.must_have_link 'Submit package'
    page.wont_have_link 'link diff'

    # try to submit unchanged sources
    click_link 'Submit package'
    page.must_have_field('targetproject', with: 'home:dmayr')
    page.wont_have_field('supersede_request_ids[]')
    check('sourceupdate')
    click_button 'Ok'
    page.wont_have_selector '.dialog' # wait for the reload
    flash_message.must_match %r{Unable to submit, sources are unchanged}

    # modify and resubmit
    Suse::Backend.put( '/source/home:adrian/x11vnc/DUMMY?user=adrian', 'DUMMY')
    click_link 'Submit package'
    page.must_have_field('targetproject', with: 'home:dmayr')
    page.wont_have_field('supersede_request_ids[]')
    check('sourceupdate')
    click_button 'Ok'

    # got a request
    page.wont_have_selector '.dialog' # wait for the reload
    flash_message.must_match %r{Created submit request \d* to home:dmayr}
    requestid = flash_message.gsub(%r{Created submit request (\d*) to home:dmayr}, '\1').to_i
    within '#flash-messages' do
      click_link 'submit request'
    end

    logout
    login_dmayr to: request_show_path(id: requestid)
    page.must_have_text 'Submit package home:adrian / x11vnc (revision'
    page.must_have_text ' to package home:dmayr / x11vnc'
    fill_in 'reason', with: 'Bad idea'
    click_button 'Decline request' # dmayr is a mean bastard
    logout

    login_adrian to: package_show_path(project: 'home:adrian', package: 'x11vnc')
    # now change something more for a second request
    find(:css, "tr##{valid_xml_id('file-README')} td:first-child a").click
    page.must_have_text 'just to delete'
    # codemirror is not really test friendly, so just brute force it - we basically
    # want to test the load and save work flow not the codemirror library
    page.execute_script("editors[0].setValue('My new cool text');")
    assert !find(:css, '.buttons.save')['class'].split(' ').include?('inactive')
    find(:css, '.buttons.save').click
    page.must_have_selector('.buttons.save.inactive')
    click_link 'Overview'

    click_link 'link diff'

    page.must_have_text 'Difference Between Revision 3 and home:dmayr / x11vnc'

    click_link 'Submit to home:dmayr / x11vnc'

    page.must_have_field('targetproject', with: 'home:dmayr')
    page.must_have_field('targetpackage', with: 'x11vnc')

    within '#supersede_display' do
      page.must_have_text "#{requestid} by adrian"
    end

    page.must_have_field('supersede_request_ids[]')
    all('input[name="supersede_request_ids[]"]').each {|input| check(input[:id]) }
    click_button 'Ok'
    page.wont_have_selector '.dialog' # wait for the reload
    flash_message.must_match %r{Created submit request .* to home:dmayr}
    new_requestid = flash_message.gsub(%r{Created submit request (\d*) to home:dmayr}, '\1').to_i
    visit request_show_path(id: requestid)
    page.must_have_text "Request #{requestid} (superseded)"
    page.must_have_content "Superseded by #{new_requestid}"

    # You are not allowed to supersede requests you have no role in.
    #
    # TODO: actually it does not make sense to display requests that we can't supersede
    # but that's for later
    Suse::Backend.put( '/source/home:adrian/x11vnc/DUMMY2?user=adrian', 'DUMMY2')
    login_tom to: package_show_path(project: 'home:adrian', package: 'x11vnc')
    click_link 'Submit package'
    page.must_have_field('supersede_request_ids[]')
    all('input[name="supersede_request_ids[]"]').each {|input| check(input[:id]) }
    click_button 'Ok'
    page.wont_have_selector '.dialog' # wait for the reload
    flash_message.must_match %r{Created submit request \d* to home:dmayr}
    flash_message.must_match %r{Superseding failed: You have no role in request \d*}

    # You will not be given the option to supersede requests from other source projects
    login_tom to: project_show_path(project: 'home:tom')
    click_link 'Branch existing package'
    fill_in 'linked_project', with: 'home:dmayr'
    fill_in 'linked_package', with: 'x11vnc'
    click_button 'Create Branch'
    click_link 'Submit package'
    page.wont_have_field('supersede_request_ids[]')
  end

  def test_remove_file
    use_js

    login_dmayr to: package_show_path(project: 'home:dmayr', package: 'x11vnc')
    within 'tr#file-README' do
      find(:css, '.icons-page_white_delete').click
    end
    page.wont_have_link 'README'
    # restore now
    Suse::Backend.put( '/source/home:dmayr/x11vnc/README?user=king', 'just to delete')
  end

  def test_revisions
    visit package_view_revisions_path(project: 'BaseDistro2.0', package: 'pack2')
    click_link "Revisions"
    page.must_have_text "Revision Log of pack2 (3)"

    visit package_view_revisions_path(project: 'BaseDistro2.0', package: 'pack2', rev: '2')
    page.must_have_text "Revision Log of pack2 (2)"
    click_link "Show all"
    page.must_have_text "Revision Log of pack2 (3)"

    login_king
    20.times { |i| put '/source/BaseDistro2.0/pack2/dummy', i.to_s }
    visit package_view_revisions_path(project: 'BaseDistro2.0', package: 'pack2')
    page.must_have_text "Revision Log of pack2 (23)"
    all(:css, 'div.commit_item').count.must_equal 20
    click_link "Show all"
    all(:css, 'div.commit_item').count.must_equal 23
  end

  def test_access_live_build_log
    visit '/package/live_build_log/home:Iggy/TestPack/10.2/i586'
    page.status_code.must_equal 200
    login_Iggy to: '/package/live_build_log/SourceprotectedProject/pack/repo/i586'
    page.status_code.must_equal 200
    flash_message.must_equal 'Could not access build log'
  end
end
