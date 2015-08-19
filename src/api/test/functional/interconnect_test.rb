require File.expand_path(File.dirname(__FILE__) + '/..') + '/test_helper'
require 'source_controller'

class InterConnectTests < ActionDispatch::IntegrationTest 

  fixtures :all
   
  def setup
    wait_for_scheduler_start
  end

  def test_anonymous_access
    get '/public/lastevents' # OBS 2.1
    assert_response :success
    assert_xml_tag :tag => 'events', :attributes => {:sync => 'lost' }
    post '/public/lastevents?start=1'
    assert_response :success
    assert_xml_tag :tag => 'event', :attributes => {:type => 'project' }
    assert_no_xml_tag :tag => 'events', :attributes => {:sync => 'lost' }

    post '/public/lastevents', nil # OBS 2.3 and later
    assert_response :success
    assert_xml_tag :tag => 'events', :attributes => {:sync => 'lost' }
    post '/public/lastevents', :start => '1'
    assert_response :success
    assert_xml_tag :tag => 'event', :attributes => {:type => 'project' }
    assert_no_xml_tag :tag => 'events', :attributes => {:sync => 'lost' }

    # direct access
    get '/public/source/BaseDistro'
    assert_response :success
    get '/public/source/BaseDistro/_meta'
    assert_response :success
    get '/public/source/BaseDistro/_config'
    assert_response :success
    get '/public/source/BaseDistro/_pubkey'
    assert_response :success
    get '/public/source/BaseDistro/pack1'
    assert_response :success
    get '/public/source/BaseDistro/pack1?expand'
    assert_response :success
    get '/public/source/BaseDistro/pack1?expand=1'
    assert_response :success
    get '/public/source/BaseDistro/pack1?view=cpio'
    assert_response :success
    get '/public/source/BaseDistro/pack1/_meta'
    assert_response :success
    get '/public/source/BaseDistro/pack1/my_file'
    assert_response :success

    # direct access to remote instance
    get '/public/source/RemoteInstance:BaseDistro'
    assert_response :success
    get '/public/source/RemoteInstance:BaseDistro/_meta'
    assert_response :success
    get '/public/source/RemoteInstance:BaseDistro/_config'
    assert_response :success
    get '/public/source/RemoteInstance:BaseDistro/_pubkey'
    assert_response :success
    get '/public/source/RemoteInstance:BaseDistro/pack1'
    assert_response :success
    get '/public/source/RemoteInstance:BaseDistro/pack1?expand'
    assert_response :success
    get '/public/source/RemoteInstance:BaseDistro/pack1?expand=1'
    assert_response :success
    get '/public/source/RemoteInstance:BaseDistro/pack1/_meta'
    assert_response :success
    get '/public/source/RemoteInstance:BaseDistro/pack1/my_file'
    assert_response :success
    get '/public/build/RemoteInstance:home:Iggy/10.2/i586/pack1?view=cpio'
    assert_response :success
    get '/public/build/RemoteInstance:home:Iggy/10.2/i586/pack1?view=binaryversions'
    assert_response :success

    # and is it also working with an OBS proxy in the middle?
    get '/public/source/RemoteInstance:RemoteInstance:BaseDistro'
    assert_response :success
    get '/public/source/RemoteInstance:RemoteInstance:BaseDistro/_meta'
    assert_response :success
    get '/public/source/RemoteInstance:RemoteInstance:BaseDistro/_config'
    assert_response :success
    get '/public/source/RemoteInstance:RemoteInstance:BaseDistro/_pubkey'
    assert_response :success
    get '/public/source/RemoteInstance:RemoteInstance:BaseDistro/pack1'
    assert_response :success
    get '/public/source/RemoteInstance:RemoteInstance:BaseDistro/pack1?expand'
    assert_response :success
    get '/public/source/RemoteInstance:RemoteInstance:BaseDistro/pack1?expand=1'
    assert_response :success
    get '/public/source/RemoteInstance:RemoteInstance:BaseDistro/pack1/_meta'
    assert_response :success
    get '/public/source/RemoteInstance:RemoteInstance:BaseDistro/pack1/my_file'
    assert_response :success
    get '/public/build/RemoteInstance:RemoteInstance:home:Iggy/10.2/i586/pack1?view=cpio'
    assert_response :success
    get '/public/build/RemoteInstance:RemoteInstance:home:Iggy/10.2/i586/pack1?view=binaryversions'
    assert_response :success

    # public binary access
    get '/public/build/home:Iggy/10.2/i586/_repository?view=cache'
    assert_response :success
    get '/public/build/home:Iggy/10.2/i586/_repository?view=solvstate'
    assert_response :success
    get '/public/build/home:Iggy/10.2/i586/_repository?view=binaryversions'
    assert_response :success
    get '/public/build/home:Iggy/10.2/i586/pack1'
    assert_response :success
    get '/public/build/home:Iggy/10.2/i586/pack1?view=cpio'
    assert_response :success
    get '/public/build/home:Iggy/10.2/i586/pack1?view=binaryversions'
    assert_response :success

    # access to local project with project link to remote
    get '/public/source/UseRemoteInstance'
    assert_response :success
    get '/public/source/UseRemoteInstance/_meta'
    assert_response :success
    get '/public/source/UseRemoteInstance/pack1'
    assert_response :success
    get '/public/source/UseRemoteInstance/pack1?expand'
    assert_response :success
    get '/public/source/UseRemoteInstance/pack1?expand=1'
    assert_response :success
    get '/public/source/UseRemoteInstance/pack1/_meta'
    assert_response :success
    get '/public/source/UseRemoteInstance/pack1/my_file'
    assert_response :success
    get '/public/source/UseRemoteInstance/NotExisting'
    assert_response 404
    get '/public/source/UseRemoteInstance/NotExisting/_meta'
    assert_response 404
    get '/public/source/UseRemoteInstance/NotExisting/my_file'
    assert_response 404
  end

  def test_backend_support
    get '/public/source/UseRemoteInstance?package=pack1&package=pack2&view=info'
    assert_response :success
    assert_xml_tag( :tag => 'sourceinfo', :attributes => { :package => 'pack1' } )
    assert_xml_tag( :tag => 'sourceinfo', :attributes => { :package => 'pack2' } )
    assert_no_xml_tag( :tag => 'sourceinfo', :attributes => { :package => 'pack3' } )

    # with credentials
    login_tom
    get '/source/UseRemoteInstance?package=pack1&package=pack2&view=info'
    assert_response :success
    assert_xml_tag( :tag => 'sourceinfo', :attributes => { :package => 'pack1' } )
    assert_xml_tag( :tag => 'sourceinfo', :attributes => { :package => 'pack2' } )
    assert_no_xml_tag( :tag => 'sourceinfo', :attributes => { :package => 'pack3' } )
  end

  def test_backend_post_with_forms
    post '/public/lastevents', 'filter=pack1&filter=pack2'
    assert_response :success
  end

  def test_use_remote_repositories
    login_tom

    # use repo
    put '/source/home:tom:testing/_meta', '<project name="home:tom:testing">
	  <title />
	  <description />
	  <repository name="repo">
	    <path project="RemoteInstance:BaseDistro" repository="BaseDistroUpdateProject_repo" />
	    <arch>i586</arch>
	  </repository>
	</project> '
    assert_response :success

    # try to update remote project container
    login_king
    get '/source/RemoteInstance/_meta'
    assert_response :success
    put '/source/RemoteInstance/_meta', @response.body.dup
    assert_response :success

    # cleanup     
    delete '/source/home:tom:testing'
    assert_response :success
  end

  def test_read_and_command_tests
    login_tom
    get '/source'
    assert_response :success

    # direct access to remote instance
    get '/source/RemoteInstance:BaseDistro'
    assert_response :success
    get '/source/RemoteInstance:BaseDistro/_meta'
    assert_response :success
    get '/source/RemoteInstance:BaseDistro/_pubkey'
    assert_response :success
    get '/source/RemoteInstance:BaseDistro/pack1'
    assert_response :success
    get '/source/RemoteInstance:BaseDistro/pack1/_meta'
    assert_response :success
    get '/source/RemoteInstance:BaseDistro/pack1/my_file'
    assert_response :success
    get '/source/RemoteInstance:BaseDistro/pack1?view=info&parse=1' # licensedigger needs it
    assert_response :success
    assert_xml_tag( :tag => 'sourceinfo', :attributes => { :package => 'pack1' } )
    post '/source/RemoteInstance:BaseDistro/pack1', :cmd => 'showlinked'
    assert_response :success
    post '/source/RemoteInstance:BaseDistro/pack1', :cmd => 'branch'
    assert_response :success
    get '/source/RemoteInstance:BaseDistro2.0:LinkedUpdateProject'
    assert_response :success
    assert_xml_tag( :tag => 'directory', :children => { :count => 0 } ) # backend does not provide a counter
    get '/source/RemoteInstance:BaseDistro2.0:LinkedUpdateProject?expand=1'
    assert_response :success
    assert_xml_tag( :tag => 'entry', :attributes => { :name => 'pack2', :originproject => 'RemoteInstance:BaseDistro2.0' } )
    assert_xml_tag( :tag => 'entry', :attributes => { :name => 'pack2.linked', :originproject => 'RemoteInstance:BaseDistro2.0' } )
    # test binary operations
    login_king
    post '/build/RemoteInstance:BaseDistro', :cmd => 'wipe', :package => 'pack1'
    assert_response 403
    post '/build/RemoteInstance:BaseDistro', :cmd => 'rebuild', :package => 'pack1'
    assert_response 403
    post '/build/RemoteInstance:BaseDistro', :cmd => 'wipe'
    assert_response 403
    post '/build/RemoteInstance:BaseDistro', :cmd => 'rebuild'
    assert_response 403
    # the webui requires this for repository browsing in advanced repo add mask
    get '/build/RemoteInstance:BaseDistro'
    assert_response :success
    get '/build/RemoteInstance:BaseDistro/BaseDistro_repo'
    assert_response :success
    get '/build/RemoteInstance:BaseDistro/BaseDistro_repo/i586/pack2/package-1.0-1.i586.rpm'
    assert_response :success
    get '/build/RemoteInstance:BaseDistro/BaseDistro_repo/i586/_repository'
    assert_response :success
    get '/build/RemoteInstance:BaseDistro/BaseDistro_repo/i586/_repository/package'
    assert_response :success
    get '/build/RemoteInstance:BaseDistro/BaseDistro_repo/i586'
    assert_response :success
    get '/build/RemoteInstance:BaseDistro/BaseDistro_repo/i586/pack2'
    assert_response :success
    get '/build/RemoteInstance:BaseDistro/BaseDistro_repo/i586/pack2?view=cpio'
    assert_response :success
    get '/build/RemoteInstance:BaseDistro/BaseDistro_repo/i586/pack2?view=binaryversions'
    assert_response :success
    get '/build/RemoteInstance:BaseDistro/BaseDistro_repo/i586/_repository'
    assert_response :success
    get '/build/RemoteInstance:BaseDistro/BaseDistro_repo/i586/_repository?view=cache'
    assert_response :success
    get '/build/RemoteInstance:BaseDistro/BaseDistro_repo/i586/_repository?view=solvstate'
    assert_response :success
    get '/build/RemoteInstance:BaseDistro/BaseDistro_repo/i586/_repository?view=binaryversions'
    assert_response :success
    get '/build/RemoteInstance:BaseDistro/_result?package=pack1&lastbuild=1' # for licensedigger
    assert_response :success
    assert_xml_tag( :tag => 'result', :attributes => { :project => "BaseDistro", :repository => 'BaseDistro_repo', :arch => 'i586' } )
    get "/build/RemoteInstance:BaseDistro/_result?view=summary"
    assert_response :success
    assert_xml_tag( :tag => 'result', :attributes => { :project => "BaseDistro", :repository => 'BaseDistro_repo', :arch => 'i586' } )
    assert_xml_tag( :tag => 'summary' )

    # direct access to remote instance, not existing project/package
    login_tom
    get '/source/RemoteInstance:NotExisting/_meta'
    assert_response 404
    get '/source/RemoteInstance:NotExisting/pack1'
    assert_response 404
    get '/source/RemoteInstance:NotExisting/pack1/_meta'
    assert_response 404
    get '/source/RemoteInstance:NotExisting/pack1/my_file'
    assert_response 404
    get '/source/RemoteInstance:BaseDistro/NotExisting'
    assert_response 404
    get '/source/RemoteInstance:BaseDistro/NotExisting/_meta'
    assert_response 404
    get '/source/RemoteInstance:BaseDistro/NotExisting/my_file'
    assert_response 404
    get '/source/RemoteInstance:kde4/_pubkey'
    assert_response 404
    assert_match(/no pubkey available/, @response.body)

    # access to local project with project link to remote, and via a local indirection
    %w(UseRemoteInstance UseRemoteInstanceIndirect).each do |project|
      get "/source/#{project}"
      assert_response :success
      get "/source/#{project}/_meta"
      assert_response :success
      get "/source/#{project}/pack1"
      assert_response :success
      get "/source/#{project}/pack1/_meta"
      assert_response :success
      get "/source/#{project}/pack1/my_file"
      assert_response :success
      post "/source/#{project}/pack1", :cmd => 'showlinked'
      assert_response :success
      post "/source/#{project}/pack1", :cmd => 'branch'
      assert_response :success
      get "/source/#{project}"
      assert_response :success
      assert_xml_tag( :tag => 'directory', :attributes => { :count => '0' } )
      get "/source/#{project}?expand=1"
      assert_response :success
if $ENABLE_BROKEN_TEST
#FIXME2.4: remote packages get not added yet.
      assert_xml_tag( :tag => 'directory', :attributes => { :count => '1' } )
      assert_xml_tag( :tag => 'entry', :attributes => { :name => 'pack1', :originproject => 'BaseDistro2.0' } )
end
    end

    # check access to binaries of remote instance
    get '/build/UseRemoteInstance/pop/i586/pack1/_log'
    assert_response 400
    assert_match(/remote error: pack1  no logfile/, @response.body) # we had no build, but request reached backend
    # test source modifications
    post '/build/UseRemoteInstance/pack1', :cmd => 'set_flag'
    assert_response 403
    post '/build/UseRemoteInstance/pack1', :cmd => 'unlock'
    assert_response 403
    get '/source/UseRemoteInstance/NotExisting'
    assert_response 404
    get '/source/UseRemoteInstance/NotExisting/_meta'
    assert_response 404
    get '/source/UseRemoteInstance/NotExisting/my_file'
    assert_response 404
    # test binary operations
    login_king
    post '/build/UseRemoteInstance', :cmd => 'wipe', :package => 'pack1'
    assert_response :success
    post '/build/UseRemoteInstance', :cmd => 'rebuild', :package => 'pack1'
    assert_response :success
    post '/build/UseRemoteInstance', :cmd => 'wipe'
    assert_response :success
    post '/build/UseRemoteInstance', :cmd => 'rebuild'
    assert_response :success

    # access via a local package linking to a remote package
    login_tom
    get '/source/LocalProject/remotepackage'
    assert_response :success
    ret = Xmlhash.parse(@response.body)['linkinfo']
    xsrcmd5 = ret['xsrcmd5']
    assert_not_nil xsrcmd5
    post '/source/LocalProject/remotepackage', :cmd => 'showlinked'
    assert_response :success
    get '/source/LocalProject/remotepackage/_meta'
    assert_response :success
    get '/source/LocalProject/remotepackage/my_file'
    assert_response 404
    get '/source/LocalProject/remotepackage/_link'
    assert_response :success
    ret = Xmlhash.parse(@response.body)
    assert_equal 'RemoteInstance:BaseDistro', ret['project']
    assert_equal 'pack1', ret['package']
    get "/source/LocalProject/remotepackage/my_file?rev=#{xsrcmd5}"
    assert_response :success
    post '/source/LocalProject/remotepackage', :cmd => 'branch'
    assert_response :success
    get "/source/LocalProject/remotepackage/_link?rev=#{xsrcmd5}"
    assert_response 404
    get '/source/LocalProject/remotepackage/not_existing'
    assert_response 404
    # test binary operations
    login_king
    post '/build/LocalProject', :cmd => 'wipe', :package => 'remotepackage'
    assert_response :success
    post '/build/LocalProject', :cmd => 'rebuild', :package => 'remotepackage'
    assert_response :success
    post '/build/LocalProject', :cmd => 'wipe'
    assert_response :success
    post '/build/LocalProject', :cmd => 'rebuild'
    assert_response :success
  end

  def test_invalid_submit_to_remote_instance
    login_king
    post '/request?cmd=create', '<request>
                                   <action type="submit">
                                     <source project="BaseDistro" package="pack1" rev="1"/>
                                     <target project="RemoteInstance:home:tom" package="pack1"/>
                                   </action>
                                   <state name="new" />
                                 </request>'
    assert_response 400
    assert_xml_tag :tag => 'status', :attributes => { :code => 'remote_target' }
  end

  def test_submit_requests_from_remote

    login_king
    post '/source/LocalProject/pack1', :cmd => :copy, :oproject => 'LocalProject', :opackage => 'remotepackage'
    assert_response :success

    login_tom
    # FIXME: submission from a remote project is not yet supported "RemoteInstance:BaseDistro"
    %w(LocalProject UseRemoteInstance).each do |prj|
      post '/request?cmd=create', '<request>
                                   <action type="submit">
                                     <source project="' + prj + '" package="pack1" rev="1"/>
                                     <target project="home:tom" package="pack1"/>
                                   </action>
                                   <state name="new" />
                                 </request>'
      assert_response :success
      node = ActiveXML::Node.new(@response.body)
      assert node.has_attribute?(:id)
      id = node.value('id')

      # ignores the review state
      post "/request/#{id}?cmd=changestate&newstate=accepted"
      assert_response :success

      delete '/source/home:tom/pack1'
      assert_response :success
    end

    login_king
    delete '/source/LocalProject/pack1'
    assert_response :success
  end

  def test_copy_and_diff_package
    # do copy commands twice to test it with existing target and without
    login_tom
    post '/source/LocalProject/temporary', :cmd => :copy, :oproject => 'LocalProject', :opackage => 'remotepackage'
    assert_response :success
    post '/source/LocalProject/temporary', :cmd => :copy, :oproject => 'LocalProject', :opackage => 'remotepackage'
    assert_response :success
    delete '/source/LocalProject/temporary'
    assert_response :success
    post '/source/LocalProject/temporary', :cmd => :copy, :oproject => 'UseRemoteInstance', :opackage => 'pack1'
    assert_response :success
    post '/source/LocalProject/temporary', :cmd => :copy, :oproject => 'RemoteInstance:BaseDistro', :opackage => 'pack1'
    assert_response :success

    post '/source/LocalProject/temporary', :cmd => :diff, :oproject => 'LocalProject', :opackage => 'remotepackage'
    assert_response :success
    post '/source/LocalProject/temporary', :cmd => :diff, :oproject => 'UseRemoteInstance', :opackage => 'pack1'
    assert_response :success
  end

  def test_diff_package
    login_tom

# FIXME: not supported in api atm
#    post "/source/RemoteInstance:BaseDistro/pack1", :cmd => :branch, :target_project => "LocalProject", :target_package => "branchedpackage"
#    assert_response :success

    Suse::Backend.put( '/source/LocalProject/newpackage/_meta?user=king', Package.find_by_project_and_name('LocalProject', 'newpackage').to_axml)
    Suse::Backend.put( '/source/LocalProject/newpackage/new_file?user=king', 'adding stuff')
    post '/source/LocalProject/newpackage', :cmd => :diff, :oproject => 'RemoteInstance:BaseDistro', :opackage => 'pack1'
    assert_response :success
  end

# FIXME: backend does not support project copy from remote
# def test_copy_project
#   login_tom
#   get "/source/RemoteInstance:BaseDistro"
#   assert_response :success
#   post "/source/home:tom:TEMPORARY?cmd=copy&oproject=RemoteInstance:BaseDistro&nodelay=1"
#   assert_response :success
#   get "/source/home:tom:TEMPORARY"
#   assert_response :success
#   delete "/source/home:tom:TEMPORARY"
#   assert_response :success
# end

  def test_get_packagelist_with_hidden_remoteurlproject
    login_tom
    get '/source/HiddenRemoteInstance'
    assert_response 404
    get '/source/HiddenRemoteInstance:BaseDistro'
    assert_response 404
    reset_auth
    prepare_request_with_user 'hidden_homer', 'homer'
    get '/source/HiddenRemoteInstance'
    assert_response :success
    get '/source/HiddenRemoteInstance:BaseDistro'
    assert_response :success
  end

  def test_read_access_hidden_remoteurlproject_index
    login_tom
    get '/build/HiddenRemoteInstance:BaseDistro/BaseDistro_repo/i586/_repository'
    assert_response 404
    get '/build/HiddenRemoteInstance:BaseDistro/BaseDistro_repo/i586/_repository?view=cache'
    assert_response 404
    get '/build/HiddenRemoteInstance:BaseDistro/BaseDistro_repo/i586/_repository?view=binaryversions'
    assert_response 404
    get '/build/HiddenRemoteInstance:BaseDistro/BaseDistro_repo/i586/_repository?view=cpio'
    assert_response 404
    get '/build/HiddenRemoteInstance:BaseDistro/BaseDistro_repo/i586/pack1'
    assert_response 404
    reset_auth
    prepare_request_with_user 'hidden_homer', 'homer'
    get '/build/HiddenRemoteInstance:BaseDistro/BaseDistro_repo/i586/_repository'
    assert_response :success
    get '/build/HiddenRemoteInstance:BaseDistro/BaseDistro_repo/i586/_repository?view=cache'
    assert_response :success
    get '/build/HiddenRemoteInstance:BaseDistro/BaseDistro_repo/i586/_repository?view=binaryversions'
    assert_response :success
    get '/build/HiddenRemoteInstance:BaseDistro/BaseDistro_repo/i586/_repository?view=cpio'
    assert_response :success
    get '/build/HiddenRemoteInstance:BaseDistro/BaseDistro_repo/i586/pack1'
    assert_response :success
  end

  def test_setup_remote_propject
    p='<project name="home:tom:remote"> <title/> <description/>  <remoteurl>http://localhost</remoteurl> </project>'

    login_tom
    put '/source/home:tom:remote/_meta', p
    assert_response 403

    login_king
    put '/source/home:tom:remote/_meta', p
    assert_response :success
    p='<project name="home:tom:remote"> <title/> <description/>  <remoteurl>http://localhost2</remoteurl> </project>'
    put '/source/home:tom:remote/_meta', p
    assert_response :success
    get '/source/home:tom:remote/_meta'
    assert_response :success
    assert_xml_tag :tag => 'remoteurl', :content => 'http://localhost2'
    p='<project name="home:tom:remote"> <title/> <description/>  </project>'
    put '/source/home:tom:remote/_meta', p
    assert_response :success

    #cleanup
    delete '/source/home:tom:remote'
    assert_response :success
  end

  def test_check_meta_stripping
    login_Iggy
    # package meta
    get '/source/home:Iggy/TestPack/_meta'
    assert_response :success
    assert_xml_tag :tag => 'person'
    get '/source/RemoteInstance:home:Iggy/TestPack/_meta'
    assert_response :success
    assert_no_xml_tag :tag => 'person'

    # project meta
    get '/source/home:Iggy/_meta'
    assert_response :success
    assert_xml_tag :tag => 'person'
    get '/source/RemoteInstance:home:Iggy/_meta'
    assert_response :success
    assert_no_xml_tag :tag => 'person'
  end

  def test_remove_broken_link
    login_Iggy
    put '/source/home:Iggy/TestLinkPack/_meta', "<package project='home:Iggy' name='TestLinkPack'> <title/> <description/> </package>"
    assert_response :success
    put '/source/home:Iggy/TestLinkPack/_link', "<link project='RemoteInstance:home:Iggy' package='TestPack' rev='invalid' />"
    assert_response :success
    get '/source/home:Iggy/TestLinkPack'
    assert_response :success
    get '/source/RemoteInstance:home:Iggy/TestLinkPack'
    assert_response 400 # always expanded against remote
    get '/source/home:Iggy/TestLinkPack?expand=1'
    assert_response 400

    delete '/source/home:Iggy/TestLinkPack/_link'
    assert_response :success

    delete '/source/home:Iggy/TestLinkPack'
    assert_response :success
  end

  def test_submit_from_remote
    login_Iggy
    raw_post '/request?cmd=create', "<request><action type='submit'><source project='RemoteInstance:home:Iggy' package='TestPack'/><target project='home:Iggy' package='TEMPORARY'/></action></request>"
    assert_response :success
    id = Xmlhash.parse(@response.body)['id']
    post "/request/#{id}?cmd=changestate&newstate=accepted"
    assert_response :success

    get '/source/home:Iggy/TEMPORARY/TestPack.spec'
    assert_response :success
    delete '/source/home:Iggy/TEMPORARY'
    assert_response :success

    # cleanup option can not work, do not allow to create requests
    raw_post '/request?cmd=create', "<request><action type='submit'><source project='RemoteInstance:home:Iggy' package='TestPack'/><target project='home:Iggy' package='TEMPORARY'/> <options><sourceupdate>cleanup</sourceupdate></options></action></request>"
    assert_response 400
    assert_xml_tag :tag => 'status', :attributes => { :code => 'not_supported' }
  end
end
