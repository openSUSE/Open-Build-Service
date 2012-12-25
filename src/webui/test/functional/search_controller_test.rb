# -*- coding: utf-8 -*-
#
require File.expand_path(File.dirname(__FILE__) + "/..") + "/test_helper"        

class SearchControllerTest < ActionDispatch::IntegrationTest

  def validate_search_page
    page.must_have_selector '#header-logo'
    page.must_have_text "Search"
    page.must_have_text "Advanced"
  end

  def search options  
    validate_search_page
    find("#advanced_link").click

    options[:for]    ||= [:projects, :packages]
    options[:in]     ||= [:name]
    options[:expect] ||= :success

    fill_in "search_input", with: options[:text]

    page.find(:id, 'project').set(options[:for].include?(:projects))
    page.find(:id, 'package').set(options[:for].include?(:packages))
    page.find(:id, 'name').set(options[:in].include?(:name))
    page.find(:id, 'title').set(options[:in].include?(:title))
    page.find(:id, 'description').set(options[:in].include?(:description))

    if options[:attribute]
      select(options[:attribute], from: "attribute_list")
    end
    click_button "search_button"

    if options[:expect] == :success
      if !options[:text].blank?
        search_details = "for \"#{options[:text]}\""
        if options[:attribute]
          search_details += " with \"#{options[:attribute]}\""
        end
      else
        search_details = "with attribute \"#{options[:attribute]}\""
      end
      find("div#content h3").must_have_text %r{^Search results #{search_details}}
    elsif options[:expect] == :invalid_search_text
      flash_message.must_equal "Search string must contain at least two characters."
      flash_message_type.must_equal :alert
      validate_search_page
    elsif options[:expect] == :invalid_search_options
      flash_message.must_equal "You have to search for #{options[:text]} in something. Click the advanced button..."
      flash_message_type.must_equal :alert
      assert search_results.empty?
      validate_search_page
    elsif options[:expect] == :no_results
      flash_message.must_equal "Your search did not return any results."
      flash_message_type.must_equal :info
      assert search_results.empty?
      validate_search_page
    end
  end

  def search_results
    raw_results = page.all("div.search_result")
    raw_results.collect do |row|
      theclass = row.first("img")["class"]
      case theclass
      when "project"
        { :type         => :project,
          :project_name => row.find("a.data-title")[:title],
          :project_title => row.find("a.data-title").text
        }
      when "package"
        { :type         => :package, 
          :package_name => row.find("a.data-title")[:title],
          :project_name => row.find("span.data-project").text
        }
      else
        fail "Unrecognized result icon. #{alt}"
      end
    end
  end

  test "find_search_link_in_footer" do
    visit "/"
    find(:css, "div#footer a.search-link").click
    validate_search_page
  end
  
  test "basic_search_functionality" do
    visit '/search'
    validate_search_page

    visit '/search?search_text=Base'
    page.must_have_text(/Base.* distro without update project/)
    page.must_have_link 'kdebase'
  end

  test "search_by_baseurl" do
    visit '/search?search_text=obs://build.opensuse.org/openSUSE:Factory/standard/fd6e76cd402226c76e65438a5e3df693-bash'
    find('#flash-messages').must_have_text "Project not found: openSUSE:Factory"

    visit '/search?search_text=obs://foo'
    find('#flash-messages').must_have_text(%{This disturl does not compute!})
  end

  test "search_for_home_projects" do
  
    visit search_path

    search(
      :text => "Home",
      :for  => [:projects],
      :in   => [:title])

    results = search_results
    # tom set no description
    assert !results.include?(:type => :project, :project_name => "home:tom", :project_title => "Этёам вокябюч еюж эи")
    assert results.include? :type => :project, :project_name => "home:Iggy", :project_title => "Iggy Home Project"
    assert results.include? :type => :project, :project_name => "home:adrian", :project_title => "adrian's Home Project"
    # important match as it's having "home" and not "Home"
    assert results.include? :type => :project, :project_name => "home:dmayr", :project_title => "my home project"
    assert results.include? :type => :project, :project_name => "home:Iggy:branches:kde4", :project_title => "Iggy Home Project"
    # the api fixtures add home dirs too
    assert results.count >= 4
  end


  test "search_for_subprojects" do

    visit search_path

    search(
      :text => "branches", 
      :for  => [:projects], 
      :in   => [:name])

    results = search_results
    assert results.include? :type => :project, :project_name => "home:Iggy:branches:kde4", :project_title => "Iggy Home Project"
    results.count.must_equal 1
  end


  test "search_for_public_projects" do

    visit search_path

    search(
      :text => "Local", 
      :for  => [:projects], 
      :in   => [:name])

    results = search_results
    assert results.include? :type => :project, :project_name => "LocalProject", :project_title => "This project is a local project"
    results.count.must_equal 1
  end


  test "search_for_packages" do

    visit search_path

    search(
      :text => "Test",
      :for  => [:packages], 
      :in   => [:name])
    
    results = search_results
    assert results.include? :type => :package, :project_name => "CopyTest", :package_name => "test"
    assert results.include? :type => :package, :project_name => "home:Iggy", :package_name => "TestPack"
    assert results.include? :type => :package, :project_name => "home:Iggy", :package_name => "ToBeDeletedTestPack"
    results.count.must_equal 3
  end
  

  test "search_by_title" do
    #TODO
  end


  test "search by description" do
    #TODO
  end


  test "search by attributes" do
    #TODO
  end


  test "search_non_existing_by_name" do

    visit search_path
  
    search(
      :text => "no such name, please!", 
      :for  => [:projects, :packages], 
      :in   => [:name],
      :expect => :no_results)
  end


  test "search_non_existing_by_title" do

    visit search_path

    search(
      :text => "Perhaps a non-existing title.", 
      :for  => [:projects, :packages], 
      :in   => [:title],
      :expect => :no_results)
  end


  test "search_non_existing_by_description" do

    visit search_path  

    search(
      :text => "Some non-existing description I hope.", 
      :for  => [:projects, :packages], 
      :in   => [:description],
      :expect => :no_results)
  end


  test "search_non_existing_by_attributes" do
    visit search_path

    search(
      :text => "", 
      :for  => [:projects, :packages], 
      :in   => [],
      :attribute => "OBS:RequestCloned",
      :expect => :no_results)
  end

  test "search_for_nothing" do
    visit search_path

    search(
      :text => "Some empty search.", 
      :for  => [:projects, :packages], 
      :in   => [:name, :title, :description],
      :expect => :no_results)
  end
  
  test "search_russian" do
    visit search_path
    
    search(
      text: "вокябюч",
      :for  => [:projects, :packages],
      :in   => [:name, :title, :description])
    
    results = search_results
    page.must_have_text "Этёам вокябюч еюж эи"
    page.must_have_text "窞綆腤 埱娵徖 渮湸湤 殠 唲堔"
    results.include?(:type => :project, :project_name => "home:tom")
    results.count.must_equal 1
  end

  test "search_in_nothing" do
    visit search_path  

    search(
      :text => "Some empty search again.", 
      :for  => [:projects, :packages], 
      :in   => [],
      :expect => :invalid_search_options)
  end
  
  
  test "search_with_empty_text" do
    visit search_path
    search(
      :text => "", 
      :for  => [:projects, :packages], 
      :in   => [:name],
      :expect => :invalid_search_text)
  end
  
end
