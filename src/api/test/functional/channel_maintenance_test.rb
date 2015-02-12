require File.expand_path(File.dirname(__FILE__) + '/..') + '/test_helper'
require 'source_controller'

class ChannelMaintenanceTests < ActionDispatch::IntegrationTest 
  fixtures :all
  
  def setup
    super
    wait_for_scheduler_start
    stub_request(:post, 'http://bugzilla.novell.com/xmlrpc.cgi').to_timeout
  end

  teardown do
    Timecop.return
  end

#
# This is one large test, which is running a full maintenance update
# This includes product channels
# And it is doing a following up update, based on released updates
#
  def test_large_channel_test
    login_king
    put '/source/BaseDistro3/pack2/file', 'NOOP'
    assert_response :success
    # setup maintained attributes
    prepare_request_with_user 'maintenance_coord', 'power'
    # single packages
    post '/source/BaseDistro2.0/pack2/_attribute', "<attributes><attribute namespace='OBS' name='Maintained' /></attributes>"
    assert_response :success
    post '/source/BaseDistro3/pack2/_attribute', "<attributes><attribute namespace='OBS' name='Maintained' /></attributes>"
    assert_response :success

    # search for maintained packages like osc is doing
    get '/search/package?match=%28%40name+%3D+%27pack2%27%29+and+%28project%2Fattribute%2F%40name%3D%27OBS%3AMaintained%27+or+attribute%2F%40name%3D%27OBS%3AMaintained%27%29'
    assert_response :success
    assert_xml_tag :tag => 'collection', :children => { count: 2 }
   
    # do the real mbranch for default maintained packages
    login_tom
    post '/source', :cmd => 'branch', :package => 'pack2'
    assert_response :success

    # validate result is done in project wide test case

    # do some file changes
    put '/source/home:tom:branches:OBS_Maintained:pack2/pack2.BaseDistro2.0_LinkedUpdateProject/new_file', 'new_content_0815'
    assert_response :success
    put '/source/home:tom:branches:OBS_Maintained:pack2/pack2.BaseDistro3/file', 'new_content_2137'
    assert_response :success

    # create maintenance request for one package
    # without specifing target, the default target must get found via attribute
    post '/request?cmd=create&addrevision=1', '<request>
                                   <action type="maintenance_incident">
                                     <source project="home:tom:branches:OBS_Maintained:pack2" package="pack2.BaseDistro3" />
                                     <options>
                                       <sourceupdate>cleanup</sourceupdate>
                                     </options>
                                   </action>
                                   <description>To fix my bug</description>
                                   <state name="new" />
                                 </request>'
    assert_response :success
    assert_no_xml_tag( :tag => 'source', :attributes => { rev: nil } )
    assert_xml_tag( :tag => 'target', :attributes => { project: 'My:Maintenance' } )
    node = ActiveXML::Node.new(@response.body)
    assert node.has_attribute?(:id)
    id1 = node.value(:id)

    # validate that request is diffable (not broken)
    post "/request/#{id1}?cmd=diff&view=xml", nil
    assert_response :success
    # the diffed packages
    assert_xml_tag( :tag => 'old', :attributes => { project: 'BaseDistro3', package: 'pack2', srcmd5: 'e4b3b98ad76a0fbcdbf888694842c149' } )
    assert_xml_tag( :tag => 'new', :attributes => { project: 'home:tom:branches:OBS_Maintained:pack2', package: 'pack2.BaseDistro3', rev: 'a645178fa01c5efa76cfba0a1e94f6ba', srcmd5: 'a645178fa01c5efa76cfba0a1e94f6ba' })
    # the diffed files
    assert_xml_tag( :tag => 'old', :attributes => { name: 'file', md5: '722d122e81cbbe543bd5520bb8678c0e', size: '4' },
                    :parent => { tag: 'file', attributes: { state: 'changed' } } )
    assert_xml_tag( :tag => 'new', :attributes => { name: 'file', md5: '6c7c49c0d7106a1198fb8f1b3523c971', size: '16' },
                    :parent => { tag: 'file', attributes: { state: 'changed' } } )
    # the expected file transfer
    assert_xml_tag( :tag => 'source', :attributes => { project: 'home:tom:branches:OBS_Maintained:pack2', package: 'pack2.BaseDistro3', rev: 'a645178fa01c5efa76cfba0a1e94f6ba' } )
    assert_xml_tag( :tag => 'target', :attributes => { project: 'My:Maintenance', releaseproject: 'BaseDistro3' } )
    # diff contains the critical lines
    assert_match( /^\-NOOP/, @response.body )
    assert_match( /^\+new_content_2137/, @response.body )

    # search as used by osc sees it
    get '/search/request', :match => 'action/@type="maintenance_incident" and (state/@name="new" or state/@name="review") and starts-with(action/target/@project, "My:Maintenance")'
    assert_response :success
    assert_xml_tag :parent => { tag: 'collection' }, :tag => 'request', :attributes => { id: id1 }

    # accept request
    prepare_request_with_user 'maintenance_coord', 'power'
    post "/request/#{id1}?cmd=changestate&newstate=accepted"
    assert_response :success

    get "/request/#{id1}"
    assert_response :success
    data = REXML::Document.new(@response.body)
    incidentProject=data.elements['/request/action/target'].attributes.get_attribute('project').to_s
    assert_not_equal incidentProject, 'My:Maintenance'

    # test build and publish flags
    get "/source/#{incidentProject}/_meta"
    assert_xml_tag :parent => { tag: 'build' }, :tag => 'disable'
    assert_xml_tag :parent => { tag: 'publish' }, :tag => 'disable'
    assert_response :success
    get "/source/#{incidentProject}/patchinfo/_meta"
    assert_response :success
    assert_xml_tag :parent => { tag: 'build' }, :tag => 'enable'
    assert_xml_tag :parent => { tag: 'publish' }, :tag => 'enable'
    assert_xml_tag :parent => { tag: 'useforbuild' }, :tag => 'disable'
    # add an old style patch name, only used via %N (in BaseDistro3Channel at the end of this test)
    get "/source/#{incidentProject}/patchinfo/_patchinfo"
    assert_response :success
    pi = ActiveXML::Node.new( @response.body )
    e = pi.add_element 'name'
    e.text = "patch_name"
    e = pi.add_element 'message'
    e.text = "During reboot a popup with a question will appear"
    put "/source/#{incidentProject}/patchinfo/_patchinfo", pi.dump_xml
    assert_response :success

    # create maintenance request with invalid target
    post '/request?cmd=create', '<request>
                                   <action type="maintenance_incident">
                                     <source project="home:tom:branches:OBS_Maintained:pack2" package="pack2.BaseDistro2.0_LinkedUpdateProject" />
                                     <target project="home:tom" />
                                   </action>
                                 </request>'
    assert_response 400
    assert_xml_tag :tag => 'status', :attributes => { code: 'no_maintenance_project' }
    # valid target..
    post '/request?cmd=create', '<request>
                                   <action type="maintenance_incident">
                                     <source project="home:tom:branches:OBS_Maintained:pack2" package="pack2.BaseDistro2.0_LinkedUpdateProject" />
                                     <target project="'+incidentProject+'" />
                                   </action>
                                 </request>'
    assert_response :success
    assert_xml_tag( :tag => 'target', :attributes => { project: incidentProject } )
    node = ActiveXML::Node.new(@response.body)
    assert node.has_attribute?(:id)
    id2 = node.value(:id)
    # ... but do not use it
    post "/request/#{id2}?cmd=changestate&newstate=revoked"
    assert_response :success

    # create maintenance request for two further packages
    # without specifing target, the default target must get found via attribute
    post '/request?cmd=create', '<request>
                                   <action type="maintenance_incident">
                                     <source project="home:tom:branches:OBS_Maintained:pack2" package="pack2.BaseDistro2.0_LinkedUpdateProject" />
                                   </action>
                                   <action type="maintenance_incident">
                                     <source project="home:tom:branches:OBS_Maintained:pack2" package="pack2.linked.BaseDistro2.0_LinkedUpdateProject" />
                                   </action>
                                   <state name="new" />
                                   <description>To fix my other bug</description>
                                 </request>'
    assert_response :success
    assert_xml_tag( :tag => 'target', :attributes => { project: 'My:Maintenance' } )
    node = ActiveXML::Node.new(@response.body)
    assert node.has_attribute?(:id)
    id2 = node.value(:id)
    post '/request?cmd=create', '<request>
                                   <action type="maintenance_incident">
                                     <source project="home:tom:branches:OBS_Maintained:pack2" package="pack2.BaseDistro2.0_LinkedUpdateProject" />
                                   </action>
                                   <action type="maintenance_incident">
                                     <source project="home:tom:branches:OBS_Maintained:pack2" package="pack2.linked.BaseDistro2.0_LinkedUpdateProject" />
                                   </action>
                                   <state name="new" />
                                   <description>To fix my other bug</description>
                                 </request>'
    assert_response :success
    assert_xml_tag( :tag => 'target', :attributes => { project: 'My:Maintenance' } )
    node = ActiveXML::Node.new(@response.body)
    assert node.has_attribute?(:id)
    id3 = node.value(:id)

    # validate that request is diffable and that the linked package is not double diffed
    post "/request/#{id2}?cmd=diff&view=xml", nil
    assert_response :success
    assert_match(/new_content_0815/, @response.body) # check if our changes are part of the diff
    assert_xml_tag :parent=>{ tag: 'file', attributes: { state: 'added' } }, :tag => 'new', :attributes=>{ name: 'new_file' }
    assert_xml_tag :parent=>{ tag: 'file', attributes: { state: 'added' } }, :tag => 'new', :attributes=>{ name: '_link' } # local link is unexpanded

    # set incident to merge into existing one
    prepare_request_with_user 'maintenance_coord', 'power'
    post "/request/#{id2}?cmd=setincident&incident=#{incidentProject.gsub(/.*:/,'')}"
    assert_response :success

    get "/request/#{id2}"
    assert_response :success
    data = REXML::Document.new(@response.body)
    maintenanceNotNewProject=data.elements['/request/action/target'].attributes.get_attribute('project').to_s
    assert_equal incidentProject, maintenanceNotNewProject

    # try to do it again
    prepare_request_with_user 'maintenance_coord', 'power'
    post "/request/#{id2}?cmd=setincident&incident=#{incidentProject.gsub(/.*:/,'')}"
    assert_response 404
    assert_xml_tag :tag => 'status', :attributes => { code: 'target_not_maintenance' }

    # accept request
    prepare_request_with_user 'maintenance_coord', 'power'
    post "/request/#{id2}?cmd=changestate&newstate=accepted&force=1" # ignore reviews and accept
    assert_response :success

    get "/request/#{id2}"
    assert_response :success
    data = REXML::Document.new(@response.body)
    maintenanceNotNewProject=data.elements['/request/action/target'].attributes.get_attribute('project').to_s
    assert_equal incidentProject, maintenanceNotNewProject

    # no patchinfo was part in source project, got it created ?
    get "/source/#{incidentProject}/patchinfo/_patchinfo"
    assert_response :success
    assert_xml_tag :tag => 'packager', :content => 'tom'
    assert_xml_tag :tag => 'description', :content => 'To fix my bug'

    #
    # Add channels
    #
    # define one
    login_king
    put '/source/BaseDistro3Channel/_meta', '<project name="BaseDistro3Channel" kind="maintenance_release"><title/><description/>
                                         <build><disable/></build>
                                         <publish><enable/></publish>
                                         <person userid="adrian_reader" role="reviewer" />
                                         <repository name="channel_repo">
                                           <arch>i586</arch>
                                         </repository>
                                   </project>'
    assert_response :success
    put '/source/BaseDistro3Channel/_config', "Repotype: rpm-md-legacy\nType: spec"
    assert_response :success

    raw_post '/source/BaseDistro3Channel/_attribute', "<attributes><attribute namespace='OBS' name='MaintenanceIdTemplate'><value>My-BaseDistro3Channel-%Y-%C</value></attribute></attributes>"
    assert_response :success

    put '/source/Channel/_meta', '<project name="Channel"><title/><description/>
                                   </project>'
    assert_response :success
    get '/source/My:Maintenance/_meta'
    assert_response :success
    meta = ActiveXML::Node.new( @response.body )
    meta.find_first('maintenance').add_element 'maintains', { project: 'Channel' }
    put '/source/My:Maintenance/_meta', meta.dump_xml
    assert_response :success

    # create channel package
    put '/source/Channel/BaseDistro2/_meta', '<package project="Channel" name="BaseDistro2"><title/><description/></package>'
    assert_response :success
    # set target via parameter
    post '/source/Channel/BaseDistro2?cmd=importchannel&target_project=BaseDistro3Channel&target_repository=channel_repo', '<?xml version="1.0" encoding="UTF-8"?>
        <channel>
          <binaries project="BaseDistro2.0:LinkedUpdateProject" repository="BaseDistro2LinkedUpdateProject_repo" arch="i586">
            <binary name="package" package="pack2.linked" project="BaseDistro2.0:LinkedUpdateProject" />
          </binaries>
        </channel>'
    assert_response :success
    # set target via xml
    put '/source/Channel/BaseDistro3/_meta', '<package project="Channel" name="BaseDistro3"><title/><description/></package>'
    assert_response :success
    post '/source/Channel/BaseDistro3?cmd=importchannel', '<?xml version="1.0" encoding="UTF-8"?>
        <channel>
          <target project="BaseDistro3Channel" repository="channel_repo"/>
          <binaries project="BaseDistro3" repository="BaseDistro3_repo" arch="i586">
            <binary name="does_not_exist" />
          </binaries>
        </channel>'
    assert_response :success
    get '/source/Channel/BaseDistro2/_channel'
    assert_response :success
    # it found the update project
    assert_xml_tag :tag => 'binary', :attributes => { project: 'BaseDistro2.0:LinkedUpdateProject', package: 'pack2.linked' }
    # target repo parameter worked
    assert_xml_tag :tag => 'target', :attributes => { project: 'BaseDistro3Channel', repository: 'channel_repo' }
    # create channel packages and repos
    login_adrian
    post "/source/#{incidentProject}?cmd=addchannels", nil
    assert_response 403
    prepare_request_with_user 'maintenance_coord', 'power'
    post "/source/#{incidentProject}?cmd=addchannels", nil
    assert_response :success
    get "/source/#{incidentProject}/BaseDistro2.Channel/_meta"
    assert_response :success

    # validate branch from projects with local channel repos
    get "/source/#{incidentProject}/_meta"
    assert_response :success
    assert_xml_tag :tag => "repository", :attributes => {name: "BaseDistro3Channel"}
    post "/source/#{incidentProject}/pack2.BaseDistro2.0_LinkedUpdateProject", :cmd => 'branch', :add_repositories => 1
    assert_response :success
    get "/source/home:maintenance_coord:branches:My:Maintenance:0/_meta"
    assert_response :success
    # local channel got skipped:
    assert_no_xml_tag :tag => "repository", :attributes => {name: "BaseDistro3Channel"}
    post "/source/#{incidentProject}/BaseDistro2.Channel", :cmd => 'branch', :add_repositories => 1
    assert_response :success
    get "/source/home:maintenance_coord:branches:My:Maintenance:0/_meta"
    assert_response :success
    # added by branching the channel package container
    assert_xml_tag :tag => "repository", :attributes => {name: "BaseDistro3Channel"}
    delete "/source/home:maintenance_coord:branches:My:Maintenance:0"
    assert_response :success


    # accept another request to check that addchannel is working automatically
    prepare_request_with_user 'maintenance_coord', 'power'
    post "/request/#{id3}?cmd=changestate&newstate=accepted&force=1" # ignore reviews and accept
    assert_response :success
    get "/request/#{id3}"
    assert_response :success
    data = REXML::Document.new(@response.body)
    maintenanceYetAnotherProject=data.elements['/request/action/target'].attributes.get_attribute('project').to_s
    # no cleanup
    get '/source/home:tom:branches:OBS_Maintained:pack2/pack2.linked.BaseDistro2.0_LinkedUpdateProject'
    assert_response :success
    get '/source/home:tom:branches:OBS_Maintained:pack2/pack2.BaseDistro2.0_LinkedUpdateProject'
    assert_response :success
    get "/source/#{maintenanceYetAnotherProject}"
    assert_response :success
    assert_xml_tag :tag => "entry", :attributes => { name: "BaseDistro2.Channel" }
    assert_xml_tag :tag => "entry", :attributes => { name: "pack2.BaseDistro2.0_LinkedUpdateProject" }
    assert_xml_tag :tag => "entry", :attributes => { name: "pack2.linked.BaseDistro2.0_LinkedUpdateProject" }
    assert_xml_tag :tag => "entry", :attributes => { name: "patchinfo" }
    assert_xml_tag :tag => "directory", :attributes => { count: "4" }
    # cleanup
    delete "/source/#{maintenanceYetAnotherProject}"
    assert_response :success
    # cleanup channel 2
    login_king
    delete "/source/#{incidentProject}/BaseDistro2.Channel"
    assert_response :success
    delete '/source/Channel/BaseDistro2'
    assert_response :success

    put '/source/Channel/BaseDistro3/_channel', '<?xml version="1.0" encoding="UTF-8"?>
        <channel>
          <target project="BaseDistro3Channel" repository="channel_repo" id_template="UpdateInfoTag-&#37;Y-&#37;C" />
          <target project="BaseDistro2.0:LinkedUpdateProject" repository="BaseDistro2LinkedUpdateProject_repo"><disabled/></target>
          <binaries project="BaseDistro3" repository="BaseDistro3_repo" arch="i586">
            <binary name="package" package="pack2" supportstatus="l3" />
            <binary name="does_not_exist" />
          </binaries>
        </channel>'
    assert_response :success
    get '/source/Channel/BaseDistro3/_channel'
    assert_response :success
    assert_no_xml_tag :tag => 'binary', :attributes => { project: 'BaseDistro2.0', package: 'pack2.linked' }
    assert_xml_tag :tag => 'binary', :attributes => { project: nil, package: 'pack2', supportstatus: 'l3' }

    # create channel packages and repos
    login_adrian
    post "/source/#{incidentProject}?cmd=addchannels", nil
    assert_response 403
    prepare_request_with_user 'maintenance_coord', 'power'
    post "/source/#{incidentProject}?cmd=addchannels", nil
    assert_response :success

    post "/source/#{incidentProject}?cmd=addchannels", nil
    assert_response :success
    get "/source/#{incidentProject}/BaseDistro3.Channel/_meta"
    assert_response :success
    assert_xml_tag :tag => 'enable', :attributes => { repository: 'BaseDistro3Channel' },
                   :parent => { tag: 'build' }
    get "/source/#{incidentProject}/patchinfo/_meta" # must be global enabled for publishing
    assert_xml_tag :tag => 'enable', :parent => { tag: 'publish' }
    get "/source/#{incidentProject}/_meta"
    assert_response :success
    assert_xml_tag :tag => 'path', :attributes => { project: 'BaseDistro3Channel', repository: 'channel_repo' },
                   :parent => { tag: 'repository', attributes: { name: 'BaseDistro3Channel' } }
    assert_xml_tag :tag => 'releasetarget', :attributes => { project: 'BaseDistro3Channel', repository: 'channel_repo', trigger: 'maintenance' },
                   :parent => { tag: 'repository', attributes: { name: 'BaseDistro3Channel' } }

    # create jobs, inject build results and fetch them
    run_scheduler('x86_64')
    run_scheduler('i586')
    inject_build_job( incidentProject, 'pack2.BaseDistro3', 'BaseDistro3', 'i586')
    inject_build_job( incidentProject, 'pack2.BaseDistro2.0_LinkedUpdateProject', 'BaseDistro2.0_LinkedUpdateProject', 'i586')
    inject_build_job( incidentProject, 'pack2.linked.BaseDistro2.0_LinkedUpdateProject', 'BaseDistro2.0_LinkedUpdateProject', 'i586')
    inject_build_job( incidentProject, 'pack2.BaseDistro2.0_LinkedUpdateProject', 'BaseDistro2.0_LinkedUpdateProject', 'x86_64')
    inject_build_job( incidentProject, 'pack2.linked.BaseDistro2.0_LinkedUpdateProject', 'BaseDistro2.0_LinkedUpdateProject', 'x86_64')
    run_scheduler('x86_64')
    run_scheduler('i586')
    wait_for_publisher
    get "/build/#{incidentProject}/_result"
    assert_response :success
    assert_xml_tag :parent => { tag: 'result', attributes: { repository: 'BaseDistro3', arch: 'i586', state: 'published' } }, :tag => 'status', :attributes => { package: 'patchinfo', code: 'succeeded' }
    assert_xml_tag :parent => { tag: 'result', attributes: { repository: 'BaseDistro3Channel', arch: 'i586', state: 'published' } }, :tag => 'status', :attributes => { package: 'patchinfo', code: 'succeeded' }
    # check updateinfo
    get "/build/#{incidentProject}/BaseDistro3Channel/i586/patchinfo/updateinfo.xml"
    assert_response :success
if $ENABLE_BROKEN_TEST
    # FIXME: the backend .channelinfo structure does not allow multiple targets atm, so the result is invalid here
    assert_xml_tag :parent => { tag: 'update', attributes: { from: 'maintenance_coord', status: 'stable', type: 'security', version: '1' } }, :tag => 'id', :content => "UpdateInfoTag-patch_name-0"
end

    # check published search db
    get "/search/published/binary/id?match=project='"+incidentProject+"'"
    assert_response :success
    assert_xml_tag :tag => "binary", :attributes => { name: "package", project: incidentProject, package: "patchinfo",
                                                      repository: "BaseDistro3", version: "1.0", release: "1", arch: "i586",
                                                      filename: "package-1.0-1.i586.rpm",
                                                      filepath: "My:/Maintenance:/0/BaseDistro3/i586/package-1.0-1.i586.rpm",
                                                      baseproject: "BaseDistro3", type: "rpm" }
    assert_xml_tag :tag => "binary", :attributes => { name: "package", project: incidentProject, package: "patchinfo",
                                                      repository: "BaseDistro3Channel", version: "1.0", release: "1", arch: "i586",
                                                      filename: "package-1.0-1.i586.rpm",
                                                      filepath: "My:/Maintenance:/0/BaseDistro3Channel/i586/package-1.0-1.i586.rpm",
                                                      baseproject: "BaseDistro3Channel", type: "rpm" }


    # create release request
    post '/request?cmd=create', '<request>
                                   <action type="maintenance_release">
                                     <source project="'+incidentProject+'" />
                                   </action>
                                   <state name="new" />
                                 </request>'
    assert_response :success
    assert_xml_tag :tag => "review", :attributes => { by_user: "adrian_reader", state: "new" }     # from channel
    assert_xml_tag :tag => "review", :attributes => { by_user: "fred", state: "new" }
    assert_xml_tag :tag => "review", :attributes => { by_group: "test_group", state: "new" }
    # no submit action
    assert_no_xml_tag :tag => 'action', :attributes => { type: 'submit' }
    node = ActiveXML::Node.new(@response.body)
    assert node.has_attribute?(:id)
    reqid = node.value(:id)
    # revoke try new request
    post "/request/#{reqid}?cmd=changestate&newstate=revoked"
    assert_response :success

    # and check what happens after modifing _channel file
    put '/source/My:Maintenance:0/BaseDistro3.Channel/_channel', '<?xml version="1.0" encoding="UTF-8"?>
        <channel>
          <target project="BaseDistro3Channel" repository="channel_repo" id_template="UpdateInfoTagNew-&#37;N-&#37;Y-&#37;C" />
          <binaries project="BaseDistro3" repository="BaseDistro3_repo" arch="i586">
            <binary name="package" package="pack2" project="BaseDistro3" />
          </binaries>
        </channel>'
    assert_response :success
    run_scheduler('x86_64')
    run_scheduler('i586')
    wait_for_publisher
    get "/build/#{incidentProject}/_result"
    assert_response :success
    assert_xml_tag :tag => "result", :attributes => { repository: "BaseDistro3Channel", code: "published" }
    # validate channel build results
    get "/build/#{incidentProject}/BaseDistro3Channel/i586/patchinfo"
    assert_response :success
    assert_xml_tag :tag => 'binary', :attributes => { filename: 'package-1.0-1.i586.rpm' }
    assert_xml_tag :tag => 'binary', :attributes => { filename: 'package-1.0-1.src.rpm' }
    assert_xml_tag :tag => 'binary', :attributes => { filename: 'updateinfo.xml' }
    get "/published/#{incidentProject}/BaseDistro3Channel/i586"
    assert_response :success
    assert_xml_tag :tag => 'entry', :attributes => { name: 'package-1.0-1.i586.rpm' }
    get "/published/#{incidentProject}/BaseDistro3Channel/src"
    assert_response :success
    assert_xml_tag :tag => 'entry', :attributes => { name: 'package-1.0-1.src.rpm' }
    get "/published/#{incidentProject}/BaseDistro3Channel/repodata"
    assert_response :success
    assert_xml_tag :tag => 'entry', :attributes => { name: 'filelists.xml.gz' }
    assert_xml_tag :tag => 'entry', :attributes => { name: 'other.xml.gz' }
    assert_xml_tag :tag => 'entry', :attributes => { name: 'primary.xml.gz' }
    assert_xml_tag :tag => 'entry', :attributes => { name: 'repomd.xml' }
    assert_xml_tag :tag => 'entry', :attributes => { name: 'updateinfo.xml.gz' }


    post '/request?cmd=create', '<request>
                                   <action type="maintenance_release">
                                     <source project="'+incidentProject+'" />
                                   </action>
                                   <state name="new" />
                                 </request>'
    assert_response :success
    node = ActiveXML::Node.new(@response.body)
    assert node.has_attribute?(:id)
    reqid = node.value(:id)
    # submit action
    assert_xml_tag :tag => 'target', :attributes => { project: 'Channel', package: 'BaseDistro3' },
                   :parent => { tag: 'action', attributes: { type: 'submit' } }
    # channel package is not released
    assert_no_xml_tag :tag => 'source', :attributes => { project: 'My:Maintenance:0', package: 'BaseDistro3.Channel' },
                   :parent => { tag: 'action', attributes: { type: 'maintenance_release' } }
    # but it has a source change, so submit action
    assert_xml_tag :tag => 'source', :attributes => { project: 'My:Maintenance:0', package: 'BaseDistro3.Channel' },
                   :parent => { tag: 'action', attributes: { type: 'submit' } }
    # no release patchinfo into channel
    assert_no_xml_tag :tag => 'target', :attributes => { project: 'Channel', package: 'patchinfo.0' },
                   :parent => { tag: 'action', attributes: { type: 'maintenance_release' } }
    # release of patchinfos
    assert_xml_tag :tag => 'target', :attributes => { project: 'BaseDistro2.0:LinkedUpdateProject', package: 'patchinfo.0' },
                   :parent => { tag: 'action', attributes: { type: 'maintenance_release' } }
    assert_xml_tag :tag => 'target', :attributes => { project: 'BaseDistro3', package: 'patchinfo.0' },
                   :parent => { tag: 'action', attributes: { type: 'maintenance_release' } }
    assert_xml_tag :tag => 'target', :attributes => { project: 'BaseDistro3Channel', package: 'patchinfo.0' },
                   :parent => { tag: 'action', attributes: { type: 'maintenance_release' } }

    # accept release request
    login_king
    post "/request/#{reqid}?cmd=changestate&newstate=accepted&force=1"
    assert_response :success
    get "/request/#{reqid}"
    assert_response :success
    # check for acceptinfo
#   assert_xml_tag :parent => { :tag => 'action', :attributes => { :type=> 'maintenance_release'} },
#                  :tag => 'source', :attributes => { :project=> 'My:Maintenance:0', :package=> 'pack2.BaseDistro3'},
#                  :tag => 'target', :attributes => { :project=> 'BaseDistro3', :package=> 'pack2.0'},
#                  :tag => 'acceptinfo', :attributes => { :rev=> '1', :srcmd5=> 'd4009ce72631596f0b7f691e615cfe2c', :osrcmd5 => "d41d8cd98f00b204e9800998ecf8427e" }

    # diffing works
    post "/request/#{reqid}?cmd=diff&view=xml", nil
    assert_response :success
#    assert_xml_tag :tag => 'old', :attributes => { :project=> 'BaseDistro2.0:LinkedUpdateProject', :package=> 'pack2.0'},
#                   :tag => 'new', :attributes => { :project=> 'BaseDistro2.0:LinkedUpdateProject', :package=> 'pack2.0'}
    run_scheduler('x86_64')
    run_scheduler('i586')
    wait_for_publisher

    # collect the job results
    get "/build/#{incidentProject}/_result"
    assert_response :success
    assert_xml_tag :parent => { tag: 'result', attributes: { repository: 'BaseDistro3', arch: 'i586', state: 'published' } }, :tag => 'status', :attributes => { package: 'patchinfo', code: 'locked' }
    assert_xml_tag :parent => { tag: 'result', attributes: { repository: 'BaseDistro3Channel', arch: 'i586', state: 'published' } }, :tag => 'status', :attributes => { package: 'patchinfo', code: 'locked' }

    # validate update info channel tag
    incidentID=incidentProject.gsub(/.*:/,'')
    get "/build/BaseDistro3Channel/channel_repo/i586/patchinfo.#{incidentID}/updateinfo.xml"
    assert_response :success
    # check for changed updateinfoid.
    assert_xml_tag :parent => { tag: 'update', attributes: { from: 'tom', status: 'stable', type: 'recommended', version: '1' } }, :tag => 'id', :content => "UpdateInfoTagNew-patch_name-#{Time.now.utc.year.to_s}-1"

    # repo is configured as legacy rpm-md, so we require short meta data file names
    get '/build/BaseDistro3Channel/_result'
    assert_response :success
    assert_xml_tag :tag => 'result', :attributes => {
        project: 'BaseDistro3Channel',
        repository: 'channel_repo',
        arch: 'i586',
        code: 'published',
        state: 'published' }
    get '/published/BaseDistro3Channel/channel_repo/repodata'
    assert_response :success
    assert_xml_tag :tag => 'entry', :attributes => { name: 'filelists.xml.gz' }  # by createrepo
    assert_xml_tag :tag => 'entry', :attributes => { name: 'other.xml.gz' }
    assert_xml_tag :tag => 'entry', :attributes => { name: 'primary.xml.gz' }
    assert_xml_tag :tag => 'entry', :attributes => { name: 'repomd.xml' }
    assert_xml_tag :tag => 'entry', :attributes => { name: 'updateinfo.xml.gz' } # by modifyrepo
    IO.popen("gunzip -cd #{Rails.root}/tmp/backend_data/repos/BaseDistro3Channel/channel_repo/repodata/updateinfo.xml.gz") do |io|
       node = REXML::Document.new( io.read )
    end
    assert_equal "UpdateInfoTagNew-patch_name-#{Time.now.year}-1", node.elements['/updates/update/id'].first.to_s

    # event handling
    UpdateNotificationEvents.new.perform
    get '/search/released/binary', match: "repository/[@project = 'BaseDistro3' and @name = 'BaseDistro3_repo']"
    assert_response :success
    assert_xml_tag :parent => { :tag => 'binary', :attributes =>
                     { name: 'package_newweaktags', version: "1.0", release: "1", arch: "x86_64" } },
                   :tag => 'publish', :attributes => { package: "pack2" }
    assert_no_xml_tag :parent => { :tag => 'binary', :attributes =>
                     { name: 'package_newweaktags', version: "1.0", release: "1", arch: "i586" } },
                   :tag => 'obsolete'
    assert_xml_tag :parent => { :tag => 'binary', :attributes =>
                     { name: 'package', version: "1.0", release: "1", arch: "i586" } },
                   :tag => 'build', :attributes => { time: "2014-07-03 12:26:54 UTC" }
    assert_xml_tag :parent => { :tag => 'binary', :attributes =>
                     { name: 'package', version: "1.0", release: "1", arch: "i586" } },
                   :tag => 'disturl', :content => "obs://testsuite/BaseDistro/repo/ce167c27b536e6ca39f8d951fa02a4ff-package"
    assert_xml_tag :tag => 'updatefor', :attributes => { project: "BaseDistro", product: "fixed" }

    assert_xml_tag :parent => { :tag => 'binary', :attributes =>
           { name: 'package', project: "BaseDistro3", repository: "BaseDistro3_repo", arch: "i586" } },
                   :tag => 'operation', :content => "modified"
    assert_xml_tag :parent => { :tag => 'binary', :attributes =>
           { name: 'package', project: "BaseDistro3", repository: "BaseDistro3_repo", arch: "src" } },
                   :tag => 'operation', :content => "added"
    assert_xml_tag :parent => { :tag => 'binary', :attributes =>
           { name: 'dropped', project: "BaseDistro3", repository: "BaseDistro3_repo", arch: "i586" } },
                   :tag => 'operation', :content => "added"
    # entire channel content
    get '/search/released/binary', match: "repository/[@project = 'BaseDistro3Channel']"
    assert_response :success
    assert_xml_tag :parent => { :tag => 'binary', :attributes =>
           { name: 'package', project: "BaseDistro3Channel", repository: "channel_repo", arch: "i586" } },
                   :tag => 'operation', :content => "added",
                   :tag => 'supportstatus', :content => "l3"
    assert_xml_tag :parent => { :tag => 'binary', :attributes =>
           { name: 'package', project: "BaseDistro3Channel", repository: "channel_repo", arch: "i586" } },
                   :tag => 'updateinfo', :attributes => { :id => "UpdateInfoTagNew-patch_name-#{Time.now.utc.year.to_s}-1", :version => "1" }

    # search via official updateinfo id tag
    get '/search/released/binary', match: "updateinfo/@id = 'UpdateInfoTagNew-patch_name-#{Time.now.utc.year.to_s}-1'"
    assert_response :success
    assert_xml_tag :tag => 'binary', :attributes =>
           { name: 'package', project: "BaseDistro3Channel", repository: "channel_repo", arch: "i586" }
    assert_xml_tag :tag => 'binary', :attributes =>
           { name: 'package', project: "BaseDistro3Channel", repository: "channel_repo", arch: "src" }
    assert_xml_tag :tag => 'updateinfo', :attributes =>
           { id: "UpdateInfoTagNew-patch_name-#{Time.now.utc.year.to_s}-1", version: "1" }


    #
    # A second update on top of a released one.
    # Additional channel using just a local linked package
    # 
    # setup two channels for splitted product
    put '/source/Channel/BaseDistro2/_meta', '<package project="Channel" name="BaseDistro2"><title/><description/></package>'
    assert_response :success
    # set target via parameter
    post '/source/Channel/BaseDistro2?cmd=importchannel&target_project=BaseDistro3Channel&target_repository=channel_repo', '<?xml version="1.0" encoding="UTF-8"?>
        <channel>
          <binaries project="BaseDistro2.0:LinkedUpdateProject" repository="BaseDistro2LinkedUpdateProject_repo" arch="i586">
            <binary name="package" package="pack2" project="BaseDistro2.0:LinkedUpdateProject" />
          </binaries>
        </channel>'
    assert_response :success
    put '/source/Channel/BaseDistro2SDK/_meta', '<package project="Channel" name="BaseDistro2SDK"><title/><description/></package>'
    assert_response :success
    put '/source/Channel/BaseDistro2SDK/_channel', '<?xml version="1.0" encoding="UTF-8"?>
        <channel>
          <target project="BaseDistro3Channel" repository="channel_repo" />
          <binaries project="BaseDistro2.0:LinkedUpdateProject" repository="BaseDistro2LinkedUpdateProject_repo" arch="i586">
            <binary name="package" package="pack2.linked" supportstatus="l3" />
          </binaries>
        </channel>'
    assert_response :success
    post '/request?cmd=create&addrevision=1', '<request>
                                   <action type="maintenance_incident">
                                     <source project="home:tom:branches:OBS_Maintained:pack2" package="pack2.BaseDistro2.0_LinkedUpdateProject" />
                                     <options>
                                       <sourceupdate>cleanup</sourceupdate>
                                     </options>
                                   </action>
                                   <action type="maintenance_incident">
                                     <source project="home:tom:branches:OBS_Maintained:pack2" package="pack2.linked.BaseDistro2.0_LinkedUpdateProject" />
                                     <options>
                                       <sourceupdate>cleanup</sourceupdate>
                                     </options>
                                   </action>
                                   <description>To fix my bug</description>
                                   <state name="new" />
                                 </request>'
    assert_response :success
    assert_no_xml_tag( :tag => 'source', :attributes => { rev: nil } )
    assert_xml_tag( :tag => 'target', :attributes => { project: 'My:Maintenance' } )
    node = ActiveXML::Node.new(@response.body)
    assert node.has_attribute?(:id)
    reqid2 = node.value(:id)

    # accept
    post "/request/#{reqid2}?cmd=changestate&newstate=accepted&force=1"
    assert_response :success
    get "/request/#{reqid2}"
    assert_response :success
    data = REXML::Document.new(@response.body)
    ontopofUpdateIncidentProject=data.elements['/request/action/target'].attributes.get_attribute('project').to_s
    get "/source/#{ontopofUpdateIncidentProject}"
    assert_response :success
    assert_xml_tag( :tag => 'entry', :attributes => { name: 'pack2.BaseDistro2.0_LinkedUpdateProject' } )
    assert_xml_tag( :tag => 'entry', :attributes => { name: 'pack2.linked.BaseDistro2.0_LinkedUpdateProject' } )
    assert_xml_tag( :tag => 'entry', :attributes => { name: 'BaseDistro2.Channel' } )
    assert_xml_tag( :tag => 'entry', :attributes => { name: 'BaseDistro2SDK.Channel' } )
    assert_xml_tag( :tag => 'entry', :attributes => { name: 'patchinfo' } )
    assert_xml_tag( :tag => 'directory', :attributes => { count: '5' } ) # and nothing else

    #validate cleanup
    get '/source/home:tom:branches:OBS_Maintained:pack2'
    assert_response 404

    # test retracting of released updates
    # cleans up the backend and validates that DB constraints get a cleanup
    [ 'pack2', 'pack2.0', 'pack2.linked', 'pack2.linked.0', 'patchinfo.0' ].each do |p|
      delete "/source/BaseDistro2.0:LinkedUpdateProject/#{p}"
      assert_response :success
    end
    delete '/source/BaseDistro3Channel/patchinfo.0'
    assert_response :success
    delete '/source/BaseDistro3/patchinfo.0'
    assert_response :success
    delete '/source/BaseDistro3/pack2.0'
    assert_response :success
    # reset pack2 as done in start_test_backend script
    delete '/source/BaseDistro3/pack2'
    assert_response :success
    put '/source/BaseDistro3/pack2/_meta', '<package project="BaseDistro3" name="pack2"><title/><description/></package>'
    assert_response :success
    raw_put '/source/BaseDistro3/pack2/package.spec', File.open("#{Rails.root}/test/fixtures/backend/binary/package.spec").read()
    assert_response :success

    # FIXME: re-run schedulers and check that updates got removed

    #cleanup
    login_king
    delete '/source/BaseDistro3Channel'
    assert_response 400 # incident still refers to it
    delete "/source/#{incidentProject}"
    assert_response 403 # still locked, so unlock it ...
    post "/source/#{incidentProject}", { cmd: 'unlock', comment: 'cleanup' }
    assert_response :success
    delete "/source/#{incidentProject}"
    assert_response :success
    delete "/source/#{ontopofUpdateIncidentProject}"
    assert_response :success
    delete '/source/Channel'
    assert_response :success
    delete '/source/BaseDistro3Channel'
    assert_response :success
  end

end
