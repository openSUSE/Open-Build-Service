require 'test_helper'

class Webui::ProjectHelperTest < ActiveSupport::TestCase
  include Webui::ProjectHelper

  def test_patchinfo_rating_color
    color = patchinfo_rating_color('important')
    assert_equal 'red', color
  end

  def test_patchinfo_category_color
    color = patchinfo_category_color('security')
    assert_equal 'maroon', color
  end

  def test_request_state_icon
    assert_equal map_request_state_to_flag('new'), 'flag_green'
    assert_equal map_request_state_to_flag(nil),  ''
  end

end
