require File.expand_path(File.dirname(__FILE__) + '/..') + '/test_helper'

class IssueTest < ActiveSupport::TestCase
  fixtures :all

  # rubocop:disable Metrics/LineLength
  BugGet0815 = "<?xml version=\"1.0\" ?><methodCall><methodName>Bug.get</methodName><params><param><value><struct><member><name>ids</name><value><array><data><value><string>1234</string></value><value><string>0815</string></value></data></array></value></member><member><name>permissive</name><value><i4>1</i4></value></member></struct></value></param></params></methodCall>\n"
  # rubocop:enable Metrics/LineLength

  def test_parse
    bnc = IssueTracker.find_by_name("bnc")
    url = bnc.show_url_for("0815")
    assert_equal url, "https://bugzilla.novell.com/show_bug.cgi?id=0815"
    html = bnc.get_html("<body><p>blah bnc#123 and bnc#789 and fate#9 via CVE-1974-42 </p></body>")
    # rubocop:disable Metrics/LineLength
    assert_equal html, "<body><p>blah <a href=\"https://bugzilla.novell.com/show_bug.cgi?id=123\">bnc#123</a> and <a href=\"https://bugzilla.novell.com/show_bug.cgi?id=789\">bnc#789</a> and fate#9 via CVE-1974-42 </p></body>"
    # rubocop:enable Metrics/LineLength
  end

  def test_create_and_destroy
    stub_request(:post, "http://bugzilla.novell.com/xmlrpc.cgi").
        with(body: BugGet0815).
        to_return(status: 200,
                  body: load_backend_file("bugzilla_get_0815.xml"),
                  headers: {})

    # pkg = Package.find( 10095 )
    iggy = User.find_by_email("Iggy@pop.org")
    bnc = IssueTracker.find_by_name("bnc")
    issue = Issue.create! name: '0815', issue_tracker: bnc
    issue.save!
    issue.summary = 'This unit test is not working'
    issue.state = Issue.bugzilla_state('NEEDINFO')
    issue.owner = iggy
    issue.save!
    issue.destroy
  end

  BugSearch = "<?xml version=\"1.0\" ?><methodCall><methodName>Bug.search</methodName>
               <params><param><value><struct><member><name>last_change_time</name><value>
               <dateTime.iso8601>20110729T14:00:21</dateTime.iso8601></value></member></struct>
               </value></param></params></methodCall>\n"
  BugGet = "<?xml version=\"1.0\" ?><methodCall><methodName>Bug.get</methodName><params><param>
            <value><struct><member><name>ids</name><value><array><data><value><i4>838932</i4></value>
            <value><i4>838933</i4></value><value><i4>838970</i4></value></data></array></value></member>
            <member><name>permissive</name><value><i4>1</i4></value></member>
            </struct></value></param></params></methodCall>\n"

  test "fetch issues" do
    stub_request(:post, "http://bugzilla.novell.com/xmlrpc.cgi").
        with(body: BugSearch).
        to_return(status: 200,
                  body: load_backend_file("bugzilla_response_search.xml"),
                  headers: {})

    stub_request(:post, "http://bugzilla.novell.com/xmlrpc.cgi").
        with(body: BugGet).
        to_return(status: 200,
                  body: load_backend_file("bugzilla_get_response.xml"),
                  headers: {})

    IssueTracker.update_all_issues
  end

  test "fetch cve" do
    # erase all the bugzilla fixtures
    Issue.destroy_all
    IssueTracker.find_by_kind("bugzilla").destroy!

    cve = IssueTracker.find_by_name("cve")
    cve.enable_fetch = 1
    cve.save!
    cve.issues.create! name: "CVE-1999-0001"

    stub_request(:head, "http://cve.mitre.org/data/downloads/allitems.xml.gz").
        to_return(status: 200, headers: {'Last-Modified' => 2.days.ago})

    stub_request(:get, "http://cve.mitre.org/data/downloads/allitems.xml.gz").
        to_return(status: 200, body: load_backend_file("allitems.xml.gz"),
                  headers: {'Last-Modified' => 2.days.ago})

    IssueTracker.update_all_issues
  end

  test "fetch fate" do
    # erase all the bugzilla fixtures
    Issue.destroy_all
    IssueTracker.find_by_kind("bugzilla").destroy!

    stub_request(:get, "https://features.opensuse.org//fate").
        to_return(status: 200, body: "", headers: {})

    fate = IssueTracker.find_by_name("fate")
    fate.enable_fetch = 1
    fate.save!
    fate.issues.create! name: "fate#2282"

    IssueTracker.update_all_issues
  end
end
