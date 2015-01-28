require File.expand_path(File.dirname(__FILE__) + "/..") + "/test_helper"
require 'xmlhash'

class SearchControllerTest < ActionDispatch::IntegrationTest 
  
  fixtures :all

  def setup
    super
    wait_for_scheduler_start
  end

  def test_search_unknown
    get "/search/attribute?namespace=OBS&name=FailedCommend"
    assert_response 401

    login_Iggy 
    get "/search/attribute?namespace=OBS&name=FailedCommend"
    assert_response 404
    assert_select "status[code] > summary", /Attribute Type OBS:FailedCommend does not exist/
  end

  def test_search_one_maintained_package
    get "/search/attribute?namespace=OBS&name=Maintained"
    assert_response 401

    login_Iggy
    get "/search/attribute?namespace=OBS&name=Maintained"
    assert_response :success
    assert_xml_tag tag: 'attribute', :attributes => { :name => "Maintained", :namespace => "OBS" }, :children => { :count => 1 }
    assert_xml_tag :child => { tag: 'project', :attributes => { :name => "Apache"}, :children => { :count => 1 } }
    assert_xml_tag :child => { :child => { tag: 'package', :attributes => { :name => "apache2" }, :children => { :count => 0 } } }
  end

  # there are 4 different code paths
  test "different parameters for search attribute" do
    login_Iggy
    get "/search/attribute?namespace=OBS&name=Maintained&project=home:Iggy"
    assert_response :success
    assert_xml_tag tag: 'attribute', children: { count: 0 }

    get "/search/attribute?namespace=OBS&name=Maintained&project=Apache&package=apache2"
    assert_response :success
    assert_xml_tag tag: 'attribute', children: { count: 1 }

    get "/search/attribute?namespace=OBS&name=Maintained&package=pack2"
    assert_response :success
    assert_xml_tag tag: 'attribute', children: { count: 0 }
    
    get "/search/attribute?namespace=OBS&name=Maintained&package=apache2"
    assert_response :success
    assert_xml_tag tag: 'attribute', children: { count: 1 }


    get "/search/attribute?namespace=OBS&name=Maintained"
    assert_response :success
    assert_xml_tag tag: 'attribute', children: { count: 1 }
  end 

  def test_xpath_1
    login_Iggy
    get "/search/package", match: '[@name="apache2"]'
    assert_response :success
    assert_xml_tag tag: 'collection', :children => { :count => 1 }
    assert_xml_tag :child => { tag: 'package', :attributes => { :name => 'apache2', :project => "Apache"} }

    get "/search/package/id", match: '[contains(@name,"Test")]'
    assert_response :success
    assert_xml_tag :child => { tag: 'package', :attributes => { :name => 'TestPack', :project => "home:Iggy"} }
    assert_xml_tag :child => { tag: 'package', :attributes => { :name => 'ToBeDeletedTestPack', :project => "home:Iggy"} }
    assert_xml_tag :child => { tag: 'package', :attributes => { :name => 'test', :project => "CopyTest"} }
    assert_xml_tag tag: 'collection', :children => { :count => 3 }
  end

  def test_xpath_2
    login_Iggy
    get "/search/package", match: '[attribute/@name="OBS:Maintained"]'
    assert_response :success
    assert_xml_tag tag: 'collection', :children => { :count => 1 }
    assert_xml_tag :child => { tag: 'package', :attributes => { :name => 'apache2', :project => "Apache"} }
  end

  def test_xpath_3
    login_Iggy
    get "/search/package", match: '[attribute/@name="OBS:Maintained" and @name="apache2"]'
    assert_response :success
    assert_xml_tag tag: 'collection', :attributes => { :matches => 1 }
    assert_xml_tag :child => { tag: 'package', :attributes => { :name => 'apache2', :project => "Apache"} }
    get "/search/package/id", match: '[attribute/@name="OBS:Maintained" and @name="apache2"]'
    assert_response :success
    assert_xml_tag tag: 'collection', :attributes => { :matches => 1 }
    assert_xml_tag :child => { tag: 'package', :attributes => { :name => 'apache2', :project => "Apache"} }
  end

  def test_xpath_4
    login_Iggy
    get "/search/package", match: '[attribute/@name="OBS:Maintained" and @name="Testpack"]'
    assert_response :success
    assert_xml_tag tag: 'collection', :children => { :count => 0 }
  end
  
  def test_xpath_5
    login_Iggy
    get "/search/package", match: '[devel/@project="kde4"]'
    assert_response :success
    assert_xml_tag tag: 'collection', :children => { :count => 0 }
  end

  def test_xpath_6
    login_Iggy
    get "/search/package", match: '[attribute/@name="Maintained"]'
    assert_response 400
    assert_xml_tag content: "attributes must be $NAMESPACE:$NAME"
  end

  def test_xpath_7
    login_Iggy
    get "/search/package", match: '[attribute/@name="OBS:Maintained"]'
    assert_response :success
    assert_xml_tag tag: 'collection', :children => { :count => 1 }

    login_Iggy
    get "/search/package", match: 'attribute/@name="[OBS:Maintained]"'
    assert_response :success
    assert_xml_tag tag: 'collection', :children => { :count => 0 }
  end

  def test_xpath_8
    login_Iggy
    get "/search/package", match: 'attribute/@name="[OBS:Maintained"'
    assert_response 400
    assert_xml_tag tag: 'status', :attributes => { :code => "illegal_xpath_error" }
    # fun part
    assert_xml_tag content: "#&lt;NoMethodError: undefined method `[]' for nil:NilClass&gt;"
  end


  def test_xpath_search_for_person_or_group
    # used by maintenance people
    login_Iggy
    get "/search/project", match: "(group/@role='bugowner' or person/@role='bugowner') and starts-with(@name,\"Base\"))"
    assert_response :success
    get "/search/package", match: "(group/@role='bugowner' or person/@role='bugowner') and starts-with(@project,\"Base\"))"
    assert_response :success
    get "/search/request?match=(action/@type='set_bugowner'+and+state/@name='accepted')"
    assert_response :success

    # small typo, no equal ...
    get "/search/request?match(mistake)"
    assert_response 400
    assert_xml_tag tag: 'status', :attributes => { :code => "empty_match" }
  end

  # do as the webui does
  test "involved packages" do
    login_Iggy
    get "/search/package/id", match: "(person/@userid='Iggy') or (group/@groupid='test_group')"
    assert_response :success
  end

  def test_person_searches
    # used by maintenance people
    login_Iggy
    get "/search/person", match: "(@login='Iggy')"
    assert_response :success
    assert_xml_tag tag: 'collection', :attributes => { :matches => "1" }
    assert_xml_tag :parent => { tag: 'person' }, tag: 'login', :content => "Iggy"
    assert_xml_tag :parent => { tag: 'person' }, tag: 'email', :content => "Iggy@pop.org"
    assert_xml_tag :parent => { tag: 'person' }, tag: 'realname', :content => "Iggy Pop"
    assert_xml_tag :parent => { tag: 'person' }, tag: 'state', :content => "confirmed"

    get "/search/person", match: "(@login='Iggy' or @login='tom')"
    assert_response :success
    assert_xml_tag tag: 'collection', :attributes => { :matches => "2" }

    get "/search/person", match: "(@email='Iggy@pop.org')"
    assert_response :success
    assert_xml_tag tag: 'collection', :attributes => { :matches => "1" }

    get "/search/person", match: "(@realname='Iggy Pop')"
    assert_response :success
    assert_xml_tag tag: 'collection', :attributes => { :matches => "1" }

# FIXME2.5: this will work when we turn to enums for the user state
#    get "/search/person", match: "(@state='confirmed')"
#    assert_response :success
#    assert_xml_tag tag: 'collection', :attributes => { :matches => "1" }

  end

  def test_xpath_old_osc
    # old osc < 0.137 did use the search interface wrong, but that worked ... :/
    # FIXME3.0: to be removed!
    login_Iggy
    get "/search/package_id", match: '[attribute/@name="OBS:Maintained" and @name="apache2"]'
    assert_response :success
    assert_xml_tag tag: 'collection', :attributes => { :matches => 1 }
    assert_xml_tag :child => { tag: 'package', :attributes => { :name => 'apache2', :project => "Apache"} }
    get "/search/project_id", match: '[@name="kde"]'
    assert_response :success
    assert_xml_tag tag: 'collection', :attributes => { :matches => 1 }
    assert_xml_tag :child => { tag: 'project', :attributes => { :name => 'kde' } }
  end

  # >>> Testing HiddenProject - flag "access" set to "disabled"
  def test_search_hidden_project_with_valid_user
    # user is maintainer, thus access to hidden project is allowed
    login_adrian
    get "/search/project", match: '[@name="HiddenProject"]'
    assert_response :success
    assert_xml_tag tag: 'collection', :children => { :count => 1 }
    #<project name="HiddenProject">
    assert_xml_tag :child => { tag: 'project', :attributes => { :name => 'HiddenProject'} }
  end
  def test_search_hidden_project_with_invalid_user
    # user is not maintainer - project has to be invisible
    login_Iggy
    get "/search/project", match: '[@name="HiddenProject"]'
    assert_response :success
    assert_xml_tag tag: 'collection', :children => { :count => 0 }
  end
  # <<< Testing HiddenProject - flag "access" set to "disabled"

  # >>> Testing package inside HiddenProject - flag "access" set to "disabled" in Project
  def test_search_package_in_hidden_project_with_valid_user
    # user is maintainer, thus access to hidden package is allowed
    login_adrian
    get "/search/package", match: '[@name="pack" and @project="HiddenProject"]'
    assert_response :success
    assert_xml_tag tag: 'collection', :children => { :count => 1 }
    assert_xml_tag :child => { tag: 'package', :attributes => { :name => 'pack', :project => "HiddenProject"} }
  end
  def test_search_package_in_hidden_project_as_non_maintainer
    # user is not maintainer - package has to be invisible
    login_Iggy
    get "/search/package", match: '[@name="pack" and @project="HiddenProject"]'
    assert_response :success
    assert_xml_tag tag: 'collection', :children => { :count => 0 }

    get "/search/package", match: '[@name="pack"]'
    assert_response :success
    assert_xml_tag tag: 'package', :attributes => { :project => "SourceprotectedProject", :name => "pack" }
    assert_no_xml_tag tag: 'package', :attributes => { :project => "HiddenProject", :name => "pack" }
  end
  # <<< Testing package inside HiddenProject - flag "access" set to "disabled" in Project

  def get_repos
    ret = Array.new
    col = Xmlhash.parse @response.body
    col.elements('repository') do |r|
      ret << "#{r['project']}/#{r['name']}"
    end
    return ret
  end

  def test_search_issues
    login_Iggy 
    get "/search/issue", match: '[@name="123456"]'
    assert_response :success
    assert_xml_tag :parent => { tag: 'issue'}, tag: 'name', :content => "123456"
    assert_xml_tag :parent => { tag: 'issue'}, tag: 'tracker', :content => "bnc"
    assert_xml_tag :parent => { tag: 'issue'}, tag: 'label', :content => "bnc#123456"
    assert_xml_tag :parent => { tag: 'issue'}, tag: 'state', :content => "CLOSED"
    assert_xml_tag :parent => { tag: 'owner'}, tag: 'login', :content => "fred"

    get "/search/issue", match: '[@name="123456" and @tracker="bnc"]'
    assert_response :success
    assert_xml_tag :parent => { tag: 'issue'}, tag: 'label', :content => "bnc#123456"

    # opposite order to test database joins
    get "/search/issue", match: '[@tracker="bnc" and @name="123456"]'
    assert_response :success
    assert_xml_tag :parent => { tag: 'issue'}, tag: 'label', :content => "bnc#123456"

    get "/search/issue", match: '[@name="0123456" and @tracker="bnc"]'
    assert_response :success
    assert_no_xml_tag tag: 'issue'

    get "/search/issue", match: '[@tracker="bnc" and (@name="123456" or @name="1234")]'
    assert_response :success
    assert_xml_tag tag: 'collection', :children => { :count => 2 }

    get "/search/issue", match: '[@tracker="bnc" and (@name="123456" or @name="1234") and @state="CLOSED"]'
    assert_response :success
    assert_xml_tag tag: 'collection', :children => { :count => 1 }

    get "/search/issue", match: '[owner/@login="fred"]'
    assert_response :success
    assert_xml_tag :parent => { tag: 'issue'}, tag: 'label', :content => "bnc#123456"

    get "/search/issue", match: '[owner/@email="fred@feuerstein.de"]'
    assert_response :success
    assert_xml_tag :parent => { tag: 'issue'}, tag: 'label', :content => "bnc#123456"
  end

  def test_search_repository_id
    login_Iggy 
    get "/search/repository/id"
    assert_response :success
    assert_xml_tag tag: 'collection'
    repos = get_repos
    assert repos.include?('home:Iggy/10.2')
    assert !repos.include?('HiddenProject/nada'), "HiddenProject repos public"

    login_king 
    get "/search/repository/id"
    assert_response :success
    assert_xml_tag tag: 'collection'
    repos = get_repos
    assert repos.include?('home:Iggy/10.2')
    assert repos.include?('HiddenProject/nada'), "HiddenProject repos public"
  end

  def test_osc_search_devel_package_after_request_accept
    login_Iggy

    get "/search/package", match: "([devel/[@project='Devel:BaseDistro:Update' and @package='pack2']])"
    assert_response :success
    assert_xml_tag tag: 'collection', :attributes => { :matches => 1 }
    assert_xml_tag tag: 'package', :attributes => { :project => "BaseDistro:Update", :name => "pack2" }
  end

  def test_search_request
    login_Iggy
    get "/search/request", match: "(action/target/@package='pack2' and action/target/@project='BaseDistro2.0' and action/source/@project='BaseDistro2.0' and action/source/@package='pack2.linked' and action/@type='submit')"
    assert_response :success

    # what osc may do
    get "search/request", match: "(state/@name='new' or state/@name='review') and (action/target/@project='BaseDistro2.0' or submit/target/@project='BaseDistro2.0' or action/source/@project='BaseDistro2.0' or submit/source/@project='BaseDistro2.0') and (action/target/@package='pack2.linked' or submit/target/@package='pack2_linked' or action/source/@package='pack2_linked' or submit/source/@package='pack2_linked')"
    assert_response :success

    # what osc really is doing
    get "search/request", match: "(state/@name='new' or state/@name='review') and (target/@project='BaseDistro2.0' or source/@project='BaseDistro2.0') and (target/@package='pack2.linked' or source/@package='pack2_linked')"
    assert_response :success

    # maintenance team is doing this query
    get "search/request", match: "state/@name='review' and review[@by_group='maintenance-team' and @state='new']"
    assert_response :success

    get "search/request", match: "(action/target/@project='Apache' and action/@type='submit' and state/@name='review' ) or (action/target/@project='Apache' and action/@type='maintenance_release' and state/@name='review' )"
    assert_response :success
    assert_xml_tag tag: "collection", attributes: { "matches"=> "1" }
    assert_xml_tag tag: "request", children: { count: 3, only: { tag: "review"} }

    get "/search/request", match: "[@id=#{1}]"
    assert_response :success

  end

  def test_search_request_2
    login_Iggy
    # this is not a good test - as the actual test is that didn't create bizar SQL queries, but this requires human eyes
    get "/search/request",  match: 'action/@type="submit" and (action/target/@project="Apache" or submit/target/@project="Apache") and (action/target/@package="apache2" or submit/target/@package="apache2")'
    assert_response :success

  end

  def get_package_count
    return Xmlhash.parse(@response.body).elements('package').length
  end

  def test_pagination
    login_Iggy
    get "/search/package?match=*"
    assert_response :success
    assert_xml_tag tag: 'collection'
    all_packages_count = get_package_count

    get "/search/package?match=*", :limit => 3
    assert_response :success
    assert_xml_tag tag: 'collection'
    assert get_package_count == 3

    get "/search/package?match=*", :offset => 3
    assert_response :success
    assert_xml_tag tag: 'collection'
    assert get_package_count == (all_packages_count - 3)
  end

  def test_find_owner
    login_king

    get "/search/owner"
    assert_response 400
    assert_xml_tag tag: 'status', :attributes => { :code => "no_binary" }

    # must be after first search controller call or backend might not be started on single test case runs
    wait_for_publisher()

    get "/search/owner?binary='package'"
    assert_response 400
    assert_xml_tag tag: 'status', :attributes => { :code => "attribute_not_set" }

    get "/search/owner?binary='package'&attribute='OBS:does_not_exist'"
    assert_response 404
    assert_xml_tag tag: 'status', :attributes => { :code => "unknown_attribute_type" }

    post "/source/home:Iggy/_attribute", "<attributes><attribute namespace='OBS' name='OwnerRootProject' /></attributes>"
    assert_response :success

    get "/search/owner?binary=DOES_NOT_EXIST"
    assert_response :success
    assert_xml_tag tag: 'collection', :children => { :count => 0 }

    get "/search/owner?binary=package"
    assert_response :success
    assert_xml_tag tag: 'owner', :attributes => { :rootproject => "home:Iggy", :project => "home:Iggy", :package => "TestPack" }
    assert_xml_tag tag: 'person', :attributes => { :name => "fred", :role => "maintainer" }
    assert_xml_tag tag: 'person', :attributes => { :name => "Iggy", :role => "maintainer" }
    assert_xml_tag tag: 'person', :attributes => { :name => "Iggy", :role => "bugowner" }

    get "/search/owner?binary=package&filter=bugowner"
    assert_response :success
    assert_xml_tag tag: 'owner', :attributes => { :rootproject => "home:Iggy", :project => "home:Iggy", :package => "TestPack" }
    assert_no_xml_tag tag: 'person', :attributes => { :name => "fred", :role => "maintainer" }
    assert_no_xml_tag tag: 'person', :attributes => { :name => "Iggy", :role => "maintainer" }
    assert_xml_tag tag: 'person', :attributes => { :name => "Iggy", :role => "bugowner" }

    # disable filter
    get "/search/owner?binary=package&limit=0&filter="
    assert_response :success
    assert_xml_tag tag: 'owner', :attributes => { :rootproject => "home:Iggy", :project => "home:Iggy", :package => "TestPack" }

    # search by user
    get "/search/owner?user=fred"
    assert_response :success
    assert_xml_tag tag: 'owner', :attributes => { :rootproject => "home:Iggy", :project => "home:Iggy", :package => "TestPack" }

    get "/search/owner?user=fred&filter=maintainer"
    assert_response :success
    assert_xml_tag tag: 'owner', :attributes => { :rootproject => "home:Iggy", :project => "home:Iggy", :package => "TestPack" }

    get "/search/owner?user=fred&filter=reviewer"
    assert_response :success
    assert_xml_tag tag: 'collection', :children => { :count => 0 }

    # lookup maintainers
    get "/search/owner?project=home:Iggy"
    assert_response :success
    assert_xml_tag tag: 'collection', :children => { :count => 1 }
    assert_xml_tag :parent => { tag: 'owner', :children => { :count => 2 },
                                :attributes => { :rootproject => "", :project => "home:Iggy" }},
                   tag: 'person', :attributes => { :name => "Iggy", :role => "maintainer" }

    get "/search/owner?project=home:Iggy&package=TestPack"
    assert_xml_tag tag: 'collection', :children => { :count => 2 }
    assert_xml_tag :parent => { tag: 'owner', :children => { :count => 4 },
                                :attributes => { :project => "home:Iggy", :package => "TestPack" }},
                   tag: 'person', :attributes => { :name => "fred", :role => "maintainer" }
    assert_xml_tag :parent => { tag: 'owner', :children => { :count => 4 },
                                :attributes => { :project => "home:Iggy", :package => "TestPack" }},
                   tag: 'person', :attributes => { :name => "Iggy", :role => "bugowner" }
    assert_xml_tag :parent => { tag: 'owner', :children => { :count => 4 },
                                :attributes => { :project => "home:Iggy", :package => "TestPack" }},
                   tag: 'person', :attributes => { :name => "Iggy", :role => "maintainer" }
    assert_xml_tag :parent => { tag: 'owner', :children => { :count => 4 },
                                :attributes => { :project => "home:Iggy", :package => "TestPack" }},
                   tag: 'group', :attributes => { :name => "test_group_b", :role => "maintainer" }
    assert_xml_tag :parent => { tag: 'owner', :children => { :count => 2 }},
                                :attributes => { :project => "home:Iggy" },
                   tag: 'person', :attributes => { :name => "hidden_homer", :role => "maintainer" }

    get "/search/owner?project=home:Iggy&package=TestPack&filter=bugowner"
    # no bugowner defined for the project => no owner node for the project
    assert_xml_tag tag: 'collection', :children => { :count => 1 }
    assert_xml_tag :parent => { tag: 'owner', :children => { :count => 1 },
                                :attributes => { :project => "home:Iggy", :package => "TestPack" }},
                   tag: 'person', :attributes => { :name => "Iggy", :role => "bugowner" }

    get "/search/owner?project=home:coolo:test"
    assert_xml_tag tag: 'collection', :children => { :count => 2 }
    assert_xml_tag tag: 'owner', :children => { :count => 1 }, :attributes => { :project => "home:coolo:test" }
    assert_xml_tag tag: 'owner', :children => { :count => 1 }, :attributes => { :project => "home:coolo" }

    # some illegal searches
    get "/search/owner?user=INVALID&filter=bugowner"
    assert_response 404
    assert_xml_tag tag: 'status', :attributes => { :code => "not_found" }
    get "/search/owner?user=fred&filter=INVALID"
    assert_response 404
    assert_xml_tag tag: 'status', :attributes => { :code => "not_found" }
    get "/search/owner?package=TestPack"
    assert_response 400
    assert_xml_tag tag: 'status', :attributes => { :code => "no_binary" }
    get "/search/owner?project=DOESNOTEXIST"
    assert_response 404

    # set devel package (this one has another devel package in home:coolo:test)
    pkg = Package.find_by_project_and_name "home:Iggy", "TestPack"
    pkg.develpackage = Package.find_by_project_and_name "kde4", "kdelibs"
    pkg.save

    # include devel package
    get "/search/owner?binary=package"
    assert_response :success
#    assert_no_xml_tag tag: 'owner', :attributes => { :package => nil }
    assert_xml_tag tag: 'owner', :attributes => { :project => "home:coolo:test" }
    assert_xml_tag tag: 'person', :attributes => { :name => "tom", :role => "maintainer" }

    # search again, but ignore devel package
    get "/search/owner?binary=package&devel=false"
    assert_response :success
    assert_xml_tag tag: 'owner', :attributes => { :project => "home:Iggy", :package => "TestPack" }
    assert_xml_tag tag: 'person', :attributes => { :name => "fred", :role => "maintainer" }
    assert_xml_tag tag: 'person', :attributes => { :name => "Iggy", :role => "maintainer" }
    assert_xml_tag tag: 'person', :attributes => { :name => "Iggy", :role => "bugowner" }

    # find all instances
    get "/search/owner?binary=package&limit=-1&expand=1&devel=false"
    assert_response :success
    assert_xml_tag tag: 'owner', :attributes => { :project => "home:Iggy", :package => "TestPack" }
    assert_no_xml_tag tag: 'owner', :attributes => { :project => "home:coolo:test" }

    # search via project link
    put "/source/TEMPORARY/_meta", "<project name='TEMPORARY'><title/><description/><link project='home:Iggy'/>
                                      <group groupid='test_group' role='maintainer' />
                                      <repository name='standard'>
                                        <path project='home:Iggy' repository='10.2'/>
                                        <arch>i586</arch>
                                      </repository>
                                    </project>"
    assert_response :success

    get "/search/owner?project=TEMPORARY&binary=package&limit=-1&expand=1"
    assert_response :success
    assert_xml_tag tag: 'owner', :attributes => { :project => "home:coolo:test" }
    assert_no_xml_tag tag: 'owner', :attributes => { :project => "home:Iggy" }

    get "/search/owner?project=TEMPORARY&binary=package&limit=-1&expand=1&devel=false"
    assert_response :success
    assert_xml_tag tag: 'owner', :attributes => { :project => "home:Iggy" }
    assert_no_xml_tag tag: 'owner', :attributes => { :project => "home:coolo:test" }

    # additional package
    put "/source/TEMPORARY/pack/_meta", "<package name='pack' project='TEMPORARY'><title/><description/><group groupid='test_group' role='bugowner'/></package>"
    assert_response :success
    raw_put '/source/TEMPORARY/pack/package.spec', File.open("#{Rails.root}/test/fixtures/backend/binary/package.spec").read()
    assert_response :success
    run_scheduler("i586")
    inject_build_job( "TEMPORARY", "pack", "standard", "i586" )
    run_scheduler("i586")
    wait_for_publisher()

    get "/search/owner?project=TEMPORARY&binary=package&limit=0&devel=false"
    assert_response :success
    assert_xml_tag tag: 'owner', :attributes => { :project => "home:Iggy", :package => "TestPack" }
    assert_xml_tag tag: 'owner', :attributes => { :project => "TEMPORARY", :package => "pack" }
    assert_no_xml_tag tag: 'owner', :attributes => { :project => "home:coolo:test" }
    assert_xml_tag tag: 'group', :attributes => { :name => "test_group", :role => "bugowner" }

    get "/search/owner?project=TEMPORARY&binary=package&devel=false"
    assert_response :success
    assert_no_xml_tag tag: 'owner', :attributes => { :project => "home:Iggy", :package => "TestPack" }
    assert_xml_tag tag: 'owner', :attributes => { :project => "TEMPORARY", :package => "pack" }
    assert_no_xml_tag tag: 'owner', :attributes => { :project => "home:coolo:test" }
    assert_xml_tag tag: 'group', :attributes => { :name => "test_group", :role => "bugowner" }

    get "/search/owner?project=TEMPORARY&binary=package"
    assert_response :success
    assert_no_xml_tag tag: 'owner', :attributes => { :project => "home:Iggy", :package => "TestPack" }
    assert_xml_tag tag: 'owner', :attributes => { :project => "TEMPORARY", :package => "pack" }
    assert_no_xml_tag tag: 'owner', :attributes => { :project => "home:coolo:test" }
    assert_xml_tag tag: 'group', :attributes => { :name => "test_group", :role => "bugowner" }

    get "/search/owner?project=TEMPORARY&binary=package&filter=reviewer&webui_mode=true"
    assert_response :success
    assert_xml_tag tag: 'owner', :attributes => { :rootproject => "TEMPORARY", :project => "TEMPORARY", :package => "pack" },
                   :children => { :count => 0 }
    assert_xml_tag tag: 'owner', :attributes => { :rootproject => "TEMPORARY", :project => "home:Iggy", :package => "TestPack" },
                   :children => { :count => 0 }

    # deepest package definition
    get "/search/owner?project=TEMPORARY&binary=package&limit=-1"
    assert_response :success
    assert_xml_tag tag: 'owner', :attributes => { :project => "home:coolo:test" }
    assert_no_xml_tag tag: 'owner', :attributes => { :project => "home:Iggy", :package => "TestPack" }
    assert_no_xml_tag tag: 'owner', :attributes => { :project => "TEMPORARY", :package => "pack" }

    # test fall through when higher project has the package, but no bugowner
    put "/source/TEMPORARY/pack/_meta", "<package name='pack' project='TEMPORARY'><title/><description/></package>"
    assert_response :success
    get "/search/owner?project=TEMPORARY&binary=package&filter=bugowner"
    assert_response :success
    assert_xml_tag tag: 'owner', :attributes => { :project => "home:Iggy", :package => "TestPack" }
    assert_xml_tag tag: 'person', :attributes => { :name => "Iggy", :role => "bugowner" }
    assert_no_xml_tag tag: 'owner', :attributes => { :project => "TEMPORARY", :package => "pack" }
    assert_no_xml_tag tag: 'owner', :attributes => { :project => "home:coolo:test" }
    assert_no_xml_tag tag: 'group', :attributes => { :name => "test_group", :role => "bugowner" }
    # disable a user and check that he disappears
    u=User.find_by_login "Iggy"
    u.state = User.states['unconfirmed']
    u.save!
    get "/search/owner?project=TEMPORARY&binary=package&filter=bugowner"
    assert_response :success
    assert_no_xml_tag tag: 'person', :attributes => { :name => "Iggy", :role => "bugowner" }
    u.state = User.states['confirmed']
    u.save

    # group in project meta
    get "/search/owner?project=TEMPORARY&binary=package&filter=maintainer"
    assert_response :success
    assert_xml_tag tag: 'owner', :attributes => { :project => "TEMPORARY" }
    assert_xml_tag tag: 'person', :attributes => { :name => "king", :role => "maintainer" }
    assert_xml_tag tag: 'group', :attributes => { :name => "test_group", :role => "maintainer" }

    # search for not mantainer packages
    get "/search/missing_owner"
    assert_response :success
    assert_xml_tag tag: 'collection', :children => { :count => 0 } # all defined

    get "/search/missing_owner?project=TEMPORARY"
    assert_response :success
    assert_xml_tag tag: 'collection', :children => { :count => 0 } # all defined

    get "/search/missing_owner?project=TEMPORARY&filter=bugowner"
    assert_response :success
    assert_xml_tag tag: 'missing_owner', :attributes => { :rootproject => "TEMPORARY", :project => "TEMPORARY", :package => "pack" }

    get "/search/missing_owner?project=TEMPORARY&filter=reviewer"
    assert_response :success
    assert_xml_tag tag: 'missing_owner', :attributes => { :rootproject => "TEMPORARY", :project => "TEMPORARY", :package => "pack" }

    # reset devel package setting again
    pkg.develpackage = nil
    pkg.save
    # cleanup
    delete "/source/TEMPORARY"
    assert_response :success
    delete "/source/home:Iggy/_attribute/OBS:OwnerRootProject"
    assert_response :success
  end

  def test_search_for_binary_without_definition_yet
    login_Iggy

    get "/search/owner?project=BaseDistro3&filter=bugowner&binary=package&limit=1"
    assert_response :success
    # found project container
    assert_xml_tag tag: 'owner', :attributes => { :rootproject => "BaseDistro3", :project => "BaseDistro3" }
    assert_no_xml_tag tag: 'owner', :attributes => { :package => "pack2" }

    # search with empty filter just to find the container to be set
    get "/search/owner?project=BaseDistro3&filter=&binary=package&limit=1"
    assert_response :success
    # found package container
    assert_xml_tag tag: 'owner', :attributes => { :rootproject => "BaseDistro3", :project => "BaseDistro3", :package => "pack2" }
  end

  def test_search_for_missing_role_defintions_in_all_visible_packages
    login_Iggy

    # search for not mantainer packages
    get "/search/missing_owner?project=BaseDistro&filter=bugowner"
    assert_response :success
    assert_xml_tag tag: 'missing_owner', :attributes => { :rootproject => "BaseDistro", :project => "BaseDistro", :package => "pack1" }
    assert_xml_tag tag: 'missing_owner', :attributes => { :rootproject => "BaseDistro", :project => "BaseDistro", :package => "pack2" }
    assert_xml_tag tag: 'missing_owner', :attributes => { :rootproject => "BaseDistro", :project => "BaseDistro", :package => "pack3" }

    get "/search/missing_owner?project=BaseDistro&filter=reviewer"
    assert_response :success
    assert_xml_tag tag: 'missing_owner', :attributes => { :rootproject => "BaseDistro", :project => "BaseDistro", :package => "pack1" }
    assert_xml_tag tag: 'missing_owner', :attributes => { :rootproject => "BaseDistro", :project => "BaseDistro", :package => "pack2" }
    assert_xml_tag tag: 'missing_owner', :attributes => { :rootproject => "BaseDistro", :project => "BaseDistro", :package => "pack3" }
  end

  def test_find_owner_when_binary_exist_in_Update_but_definition_is_in_GA_project
    login_king

    # must be after first search controller call or backend might not be started on single test case runs
    wait_for_publisher()

    # setup projects and packages
    put "/source/TEMPORARY:GA/_meta", "<project name='TEMPORARY:GA'><title/><description/>
                                      <repository name='standard'>
                                        <path project='home:Iggy' repository='10.2'/>
                                        <arch>i586</arch>
                                      </repository>
                                    </project>"
    assert_response :success
    put "/source/TEMPORARY:Update/_meta", "<project name='TEMPORARY:Update'><title/><description/><link project='TEMPORARY:GA'/>
                                      <repository name='standard'>
                                        <path project='home:Iggy' repository='10.2'/>
                                        <arch>i586</arch>
                                      </repository>
                                    </project>"
    assert_response :success
    put "/source/TEMPORARY:Update/package/_meta", "<package name='package' project='TEMPORARY:Update'><title/><description/> </package>"
    assert_response :success
    put "/source/TEMPORARY:GA/package/_meta", "<package name='package' project='TEMPORARY:GA'><title/><description/>
                                                 <person userid='fred' role='bugowner' />
                                               </package>"
    assert_response :success
    raw_put '/source/TEMPORARY:GA/package/package.spec', File.open("#{Rails.root}/test/fixtures/backend/binary/package.spec").read()
    assert_response :success
    raw_put '/source/TEMPORARY:Update/package/package.spec', File.open("#{Rails.root}/test/fixtures/backend/binary/package.spec").read()
    assert_response :success

    # package exists only in Update
    run_scheduler("i586")
    inject_build_job( "TEMPORARY:Update", "package", "standard", "i586" )
    run_scheduler("i586")
    wait_for_publisher()

    # search: upper hit
    get "/search/owner?binary=package&project=TEMPORARY:Update"
    assert_response :success
    assert_xml_tag :parent => { tag: 'owner', :attributes => { :rootproject => "TEMPORARY:Update", :project => "TEMPORARY:Update" } },
                   tag: "person", :attributes => { :name => "king", :role => "maintainer" }
    # search: find definition in package below without this binary
    get "/search/owner?binary=package&project=TEMPORARY:Update&filter=bugowner"
    assert_response :success
    assert_xml_tag :parent => { tag: 'owner', :attributes => { :rootproject => "TEMPORARY:Update", :project => "TEMPORARY:GA", :package => "package" } },
                   tag: "person", :attributes => { :name => "fred", :role => "bugowner" }

    # cleanup
    delete "/source/TEMPORARY:Update"
    assert_response :success
    delete "/source/TEMPORARY:GA"
    assert_response :success
  end

  test "xpath operators" do
    login_Iggy

    get '/search/request/id', match: '@id>1'
    assert_response :success
    assert_xml_tag tag: 'request', attributes: { id: '2'}
    assert_no_xml_tag tag: 'request', attributes: { id: '1'}

    get '/search/request/id', match: '@id>=2'
    assert_response :success
    assert_xml_tag tag: 'request', attributes: { id: '2'}
    assert_no_xml_tag tag: 'request', attributes: { id: '1'}

    get '/search/request/id', match: '@id<2'
    assert_response :success
    assert_no_xml_tag tag: 'request', attributes: { id: '2'}
    assert_xml_tag tag: 'request', attributes: { id: '1'}

    get '/search/request/id', match: '@id<=2'
    assert_response :success
    assert_no_xml_tag tag: 'request', attributes: { id: '3'}
    assert_xml_tag tag: 'request', attributes: { id: '2'}

    # verify it also works with dates
    get '/search/request/id', match: 'state/@when>="2012-09-02"'
    assert_response :success
    assert_xml_tag tag: 'request', attributes: { id: '2'}
    assert_no_xml_tag tag: 'request', attributes: { id: '1'}

  end

  test "xpath with two relationships" do
    login_Iggy
    get '/search/package/id', match: "person/@userid = 'adrian' and person/@role = 'maintainer'"
    assert_response :success
    assert_xml_tag tag: 'package', attributes: { project: 'kde4', name: 'kdelibs' }

    get '/search/project', match: "person/@userid = 'adrian' and person/@role = 'maintainer'"
    assert_response :success
    assert_xml_tag tag: 'project', attributes: { name: 'kde4' }
    assert_xml_tag tag: 'project', attributes: { name: 'home:adrian' }
  end
end

