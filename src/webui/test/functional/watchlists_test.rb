require File.expand_path(File.dirname(__FILE__) + "/..") + "/test_helper"

class WatchlistTest < ActionDispatch::IntegrationTest

  test "watchlists" do
    login_tom

    visit(project_show_path(project: "BaseDistro")) 

    # assert watchlist is empty
    page.execute_script("$('#menu-favorites').show();")
    all(:css, "span.icons-project").count.must_equal 0

    page.execute_script("$('#menu-favorites').show();")
    
    find(:css, "#menu-favorites").must_have_text %r{Add this project to Watchlist}
    find(:css, "#toggle_watch > span.desc").click
    page.execute_script("$('#menu-favorites').show();")

    find(:css, "#menu-favorites span.project-link").text.must_equal "BaseDistro"
    find(:css, "#menu-favorites").must_have_text %r{Remove this project from Watchlist}
    find(:css, "#toggle_watch > span.desc").click

    page.execute_script("$('#menu-favorites').show();")
    find(:css, "#menu-favorites").must_have_text %r{Add this project to Watchlist}
    find(:css, "#toggle_watch > span.desc").click

    visit project_show_path(project: "My:Maintenance")

    page.execute_script("$('#menu-favorites').show();")
    find(:css, "#menu-favorites").must_have_text %r{Add this project to Watchlist}
    find(:css, "#toggle_watch > span.desc").click

    page.execute_script("$('#menu-favorites').show();")
    first(:css, "span.icons-project").click

    find(:css, "#project_title").must_have_text %r{This is a base distro}
    # teardown
    page.execute_script("$('#menu-favorites').show();")
    find(:css, "#toggle_watch > span.desc").click
    page.execute_script("$('#menu-favorites').show();")
    within('#menu-favorites') do
      find(:link, "My:Maintenance").click
    end
    page.execute_script("$('#menu-favorites').show();")
    find(:css, "#toggle_watch > span.desc").click
    all(:css, "span.icons-project").count.must_equal 0
  end

end
