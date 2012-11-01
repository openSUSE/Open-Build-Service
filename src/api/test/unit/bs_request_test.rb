require File.expand_path(File.dirname(__FILE__) + "/..") + "/test_helper"

class BsRequestTest < ActiveSupport::TestCase

  fixtures :all

  test "if create works" do
    User.current = users( :Iggy )
    xml = '<request>
              <action type="submit">
                <source project="LocalProject" package="pack1" rev="1"/>
                <target project="home:tom" package="pack1"/>
              </action>
              <state name="new" />
          </request>'
    req = BsRequest.new_from_xml(xml)
    assert req.id.nil?
    req.save!
  end

  test "target_maintainer" do
    req = bs_requests(:missing_source_project)

    assert req.is_target_maintainer?(users(:adrian))
    assert !req.is_target_maintainer?(users(:user1))

  end

end
