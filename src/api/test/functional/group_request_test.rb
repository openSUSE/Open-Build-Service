# encoding: UTF-8
require File.expand_path(File.dirname(__FILE__) + "/..") + "/test_helper"
require 'request_controller'

class GroupRequestTest < ActionDispatch::IntegrationTest

  fixtures :all

  setup do
    Timecop.freeze(2010, 7, 12)
  end

  teardown do
    Timecop.return
  end

  def upload_request(filename)
    req = load_backend_file("request/#{filename}")
    post "/request?cmd=create", req
    assert_response :success
    node = ActiveXML::Node.new(@response.body)
    node.value :id
  end

  def test_set_and_get
    login_king
    # make sure there is at least one
    id = upload_request("group")
    get "/request/#{id}"
    assert_response :success

    # 998 is new, so the group is new too
    assert_equal({"id" => id,
                  "action" => {"type" => "group", "grouped" => {"id" => "998"}},
                  "state" =>
                      {"name" => "new", "who" => "king", "when" => "2010-07-12T00:00:00", "comment" => {}},
                  "description" => {}
                 }, Xmlhash.parse(@response.body))
    Timecop.freeze(1)

    # try to create a cycle
    post "/request/#{id}?cmd=addrequest&newid=#{id}&comment=been+there"
    assert_response 400
    assert_xml_tag(:tag => "status", :attributes => {:code => 'cant_group_in_groups'})

    # try to submit nonsense
    post "/request/#{id}?cmd=addrequest&newid=Foobar&comment=been+there"
    assert_response 400
    assert_xml_tag(:tag => "status", :attributes => {:code => 'require_id'})

    # add another 'new' one
    adi = upload_request("group_1")
    post "/request/#{id}?cmd=addrequest&newid=#{adi}&comment=role+too"
    assert_response :success
    get "/request/#{id}"
    assert_response :success

    # state didn't change, only history
    assert_equal({"id" => id,
                  "action" => {"type" => "group", "grouped" => [{"id" => "998"}, {"id" => adi}]},
                  "state" =>
                      {"name" => "new", "who" => "king", "when" => "2010-07-12T00:00:00", "comment" => {}},
                  "description" => {}
                 }, Xmlhash.parse(@response.body))
    Timecop.freeze(1)

    # now one in review
    withr = upload_request("submit_with_review")
    post "/request/#{id}?cmd=addrequest&newid=#{withr}&comment=review+too"
    assert_response :success
    get "/request/#{id}"
    assert_response :success

    # state changed to review
    assert_equal({"id" => id,
                  "action" => {"type" => "group", "grouped" => [{"id" => "998"}, {"id" => adi}, {"id" => withr}]},
                  "state" =>
                      {"name" => "review", "who" => "king", "when" => "2010-07-12T00:00:02", "comment" => {}},
                  "description" => {}
                 }, Xmlhash.parse(@response.body))
    Timecop.freeze(1)
    # group_1 should be in review too now
    get "/request/#{adi}"
    assert_response :success
    assert_equal({"id" => adi,
                  "action" => {"type" => "add_role",
                               "target" => {"project" => "Apache", "package" => "apache2"},
                               "person" => {"name" => "Iggy", "role" => "bugowner"}},
                  "state" =>
                      {"name" => "review",
                       "who" => "king",
                       "when" => "2010-07-12T00:00:02",
                       "comment" => {}},
                  "description" => {}
                 }, Xmlhash.parse(@response.body))

    # now we revoke the group and adi should be new again
    post "/request/#{id}?cmd=changestate&newstate=revoked"
    assert_response :success
    Timecop.freeze(1)
    # group_1 should be in new again
    get "/request/#{adi}"
    assert_response :success
    assert_equal({"id" => adi,
                  "action" => {"type" => "add_role",
                               "target" => {"project" => "Apache", "package" => "apache2"},
                               "person" => {"name" => "Iggy", "role" => "bugowner"}},
                  "state" =>
                      {"name" => "new",
                       "who" => "king",
                       "when" => "2010-07-12T00:00:03",
                       "comment" => "removed from group #{id}"},
                  "history" => {"name" => "review", "who" => "king", "when" => "2010-07-12T00:00:02"},

                  "description" => {}
                 }, Xmlhash.parse(@response.body))

  end

  test "remove request" do
    login_king
    id = upload_request("group")

    # now one in review
    withr = upload_request("submit_with_review")
    post "/request/#{id}?cmd=addrequest&newid=#{withr}&comment=review+too"
    assert_response :success

    get "/request/#{id}"
    assert_response :success
    assert_xml_tag(:tag => "state", :attributes => {:name => "review"})

    post "/request/#{id}?cmd=removerequest&oldid=#{withr}&comment=remove+again"
    assert_response :success

    get "/request/#{id}"
    assert_response :success
    assert_xml_tag(:tag => "state", :attributes => {:name => "new"})

  end

  test "accept reviews in group" do
    login_king
    id = upload_request("group")

    # now one in review
    withr = upload_request("submit_with_review")
    post "/request/#{id}?cmd=addrequest&newid=#{withr}&comment=review+too"
    assert_response :success

    withr2 = upload_request("submit_with_review")
    post "/request/#{id}?cmd=addrequest&newid=#{withr2}&comment=review2"
    assert_response :success

    post "/request/#{withr2}?cmd=changereviewstate&by_user=adrian&newstate=accepted"
    assert_response :success
    post "/request/#{withr2}?cmd=changereviewstate&by_group=test_group&newstate=accepted"
    assert_response :success
    get "/request/#{withr2}"
    # now it would be new - but as #{withhr} is still in review, the group blocks it
    assert_xml_tag(:tag => "state", :attributes => {:name => "review"})

    # now accept the same for withr
    post "/request/#{withr}?cmd=changereviewstate&by_user=adrian&newstate=accepted"
    assert_response :success
    post "/request/#{withr}?cmd=changereviewstate&by_group=test_group&newstate=accepted"
    assert_response :success
    get "/request/#{withr}"
    # should be new as no other review in the group blocked it
    assert_xml_tag(:tag => "state", :attributes => {:name => "new"})

    # withhr2 should be magically be new now too
    get "/request/#{withr2}"
    assert_xml_tag(:tag => "state", :attributes => {:name => "new"})

    # now comes the ugly part - reopening review in withhr should put withhr2 back in review
    post "/request/#{withr}?cmd=changereviewstate&by_user=adrian&newstate=new"
    # withhr should be in review of course
    get "/request/#{withr}"
    assert_xml_tag(:tag => "state", :attributes => {:name => "review"})
    # but also withhr2
    get "/request/#{withr2}"
    assert_xml_tag(:tag => "state", :attributes => {:name => "review"})

  end

  test "supersede replaces request" do
    login_king
    id = upload_request("group")

    withr = upload_request("submit_with_review")
    post "/request/#{id}?cmd=addrequest&newid=#{withr}&comment=review+too"
    assert_response :success

    get "/request/#{id}"
    assert_response :success
    assert_equal({"id" => id,
                  "action"=>{"type"=>"group", "grouped"=>[{"id"=>"998"}, {"id"=>withr}]},
                  "state"=>
                      {"name"=>"review",
                       "who"=>"king",
                       "when"=>"2010-07-12T00:00:00",
                       "comment"=>{}},
                  "description"=>{} }, Xmlhash.parse(@response.body))


    withr2 = upload_request("submit_with_review")
    assert_response :success

    post "/request/#{withr}?cmd=changestate&newstate=superseded&superseded_by=#{withr2}"
    assert_response :success

    # withr2 is in, withr out
    get "/request/#{id}"
    assert_response :success
    assert_equal({"id" => id,
                  "action"=>{"type"=>"group", "grouped"=>[{"id"=>"998"}, {"id"=>withr2}]},
                  "state"=>
                      {"name"=>"review",
                       "who"=>"king",
                       "when"=>"2010-07-12T00:00:00",
                       "comment"=>{}},
                  "description"=>{} }, Xmlhash.parse(@response.body))

  end

  test "accept sub request" do
    login_king
    id = upload_request("group")

    # now one in review
    withr = upload_request("add_role_with_review")
    post "/request/#{id}?cmd=addrequest&newid=#{withr}&comment=review+too"
    assert_response :success

    # it should be in review now
    get "/request/#{id}"
    assert_xml_tag(:tag => "state", :attributes => {:name => "review"})

    # now accept a subrequest - it's automatically removed
    post "/request/#{withr}?cmd=changestate&newstate=accepted&force=1"
    assert_response :success

    # and with that the group is in new again
    get "/request/#{id}"
    assert_xml_tag(:tag => "state", :attributes => {:name => "new"})
  end

  test "search groups" do
    login_king
    upload_request("group")

    get "/search/request?match=action/grouped/@id=997"
    assert_response :success
    assert_xml_tag(:tag => "collection", :attributes => {:matches => "0"})

    get "/search/request?match=action/grouped/@id=998"
    assert_response :success
    assert_xml_tag(:tag => "collection", :attributes => {:matches => "1"})
  end
end
