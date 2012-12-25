# -*- coding: utf-8 -*-
require File.expand_path(File.dirname(__FILE__) + "/..") + "/test_helper"        

class PackageEditTest < ActionDispatch::IntegrationTest

  def setup
    @package = "TestPack"
    @project = "home:Iggy"
    super
  end

  # ============================================================================
  #
  def package_title
    find(:id, "package_title").text
  end
  
  
  # ============================================================================
  #
  def package_description
    find(:id, "description_text").text
  end

  # ============================================================================
  #
  def change_package_info new_info
    assert !new_info[:title].blank? || !new_info[:description].blank?
    
    click_link('edit-description')
    
    page.must_have_text "Edit Package Information of #{@package} (Project #{@project})"
    page.must_have_text "Title:"
    page.must_have_text "Description:"

    unless new_info[:title].nil?
      fill_in "title", with: new_info[:title]
    end

    unless new_info[:description].nil?
      new_info[:description].squeeze!(" ")
      new_info[:description].gsub!(/ *\n +/ , "\n")
      new_info[:description].strip!
      fill_in "description", with: new_info[:description]
    end
    
    click_button "Save changes"

    page.must_have_text "Source Files"
    page.must_have_text "Build Results"

    unless new_info[:title].nil?
      assert_equal package_title, new_info[:title]
    end
    unless new_info[:description].nil?
      assert_equal package_description, new_info[:description]
    end

  end

  test "change_home_project_package_title" do
    
    login_Iggy
    visit package_show_path(:project => @project, :package => @package)

    change_package_info(
      :title => "My Title hopefully got changed " + Time.now.to_i.to_s)
  end

  
  test "change_home_project_package_description" do

    login_Iggy
    visit package_show_path(:project => @project, :package => @package)

    change_package_info(
      :description => "New description. Not kidding.. Brand new! " + Time.now.to_i.to_s)
  end

  
  test "change_home_project_package_info" do
    login_Iggy
    visit package_show_path(:project => @project, :package => @package)

    change_package_info(
      :title => "My Title hopefully got changed " + Time.now.to_i.to_s,
      :description => "New description. Not kidding.. Brand new! " + Time.now.to_i.to_s)
  end

end
