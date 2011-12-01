require File.expand_path(File.dirname(__FILE__) + "/..") + "/test_helper"
require 'source_controller'

class MaintenanceTests < ActionController::IntegrationTest 
  fixtures :all
  
  def test_create_maintenance_project
    ActionController::IntegrationTest::reset_auth 
    prepare_request_with_user "tom", "thunder"
    
    put "/source/home:tom:maintenance/_meta", '<project name="home:tom:maintenance" > <title/> <description/> </project>'
    assert_response :success
    put "/source/home:tom:maintenance/_meta", '<project name="home:tom:maintenance" kind="maintenance" > <title/> <description/> </project>'
    assert_response :success
    delete "/source/home:tom:maintenance"
    assert_response :success

    put "/source/home:tom:maintenance/_meta", '<project name="home:tom:maintenance" kind="maintenance" > <title/> <description/> </project>'
    assert_response :success

    # cleanup
    delete "/source/home:tom:maintenance" 
    assert_response :success
  end

  def test_branch_package
    ActionController::IntegrationTest::reset_auth 
    prepare_request_with_user "tom", "thunder"

    # branch a package which does not exist in update project via project link
    post "/source/BaseDistro/pack1", :cmd => :branch
    assert_response :success
    # check source link
    get "/source/home:tom:branches:BaseDistro:Update/pack1/_link"
    assert_response :success
    ret = ActiveXML::XMLNode.new @response.body
    assert_equal ret.project, "BaseDistro:Update"
    assert_equal ret.package, "pack1"
    assert_not_nil ret.baserev
    assert_not_nil ret.patches
    assert_not_nil ret.patches.branch

    # branch a package which does exist in update project and even have a devel package defined there
    post "/source/BaseDistro/pack2", :cmd => :branch
    assert_response :success
    # check source link
    get "/source/home:tom:branches:Devel:BaseDistro:Update/pack2/_link"
    assert_response :success
    ret = ActiveXML::XMLNode.new @response.body
    assert_equal ret.project, "Devel:BaseDistro:Update"
    assert_equal ret.package, "pack2"
    assert_not_nil ret.baserev
    assert_not_nil ret.patches
    assert_not_nil ret.patches.branch

    # branch a package which does exist in update project and a stage project is defined via project wide devel project
    post "/source/BaseDistro/pack3", :cmd => :branch
    assert_response :success
    # check source link
    get "/source/home:tom:branches:Devel:BaseDistro:Update/pack3/_link"
    assert_response :success
    ret = ActiveXML::XMLNode.new @response.body
    assert_equal ret.project, "Devel:BaseDistro:Update"
    assert_equal ret.package, "pack3"
    assert_not_nil ret.baserev
    assert_not_nil ret.patches
    assert_not_nil ret.patches.branch

    # branch a package which does not exist in update project, but update project is linked
    post "/source/BaseDistro2.0/pack2", :cmd => :branch
    assert_response :success
    # check source link
    get "/source/home:tom:branches:BaseDistro2.0:LinkedUpdateProject/pack2/_link"
    assert_response :success
    ret = ActiveXML::XMLNode.new @response.body
    assert_equal ret.project, "BaseDistro2.0:LinkedUpdateProject"
    assert_equal ret.package, "pack2"

    # check if we can upload a link to a packge only exist via project link
    put "/source/home:tom:branches:BaseDistro2.0:LinkedUpdateProject/pack2/_link", @response.body
    assert_response :success

    #cleanup
    delete "/source/home:tom:branches:Devel:BaseDistro:Update"
    assert_response :success
  end

  def test_mbranch_and_maintenance_request
    prepare_request_with_user "king", "sunflower"
    put "/source/ServicePack/_meta", "<project name='ServicePack'><title/><description/><link project='kde4'/></project>"
    assert_response :success

    # setup maintained attributes
    prepare_request_with_user "maintenance_coord", "power"
    # an entire project
    post "/source/BaseDistro/_attribute", "<attributes><attribute namespace='OBS' name='Maintained' /></attributes>"
    assert_response :success
    # single packages
    post "/source/BaseDistro2.0/pack2/_attribute", "<attributes><attribute namespace='OBS' name='Maintained' /></attributes>"
    assert_response :success
    post "/source/BaseDistro3/pack2/_attribute", "<attributes><attribute namespace='OBS' name='Maintained' /></attributes>"
    assert_response :success
    post "/source/ServicePack/_attribute", "<attributes><attribute namespace='OBS' name='Maintained' /></attributes>"
    assert_response :success

    # search for maintained packages like osc is doing
    get "/search/package?match=%28%40name+%3D+%27pack2%27%29+and+%28project%2Fattribute%2F%40name%3D%27OBS%3AMaintained%27+or+attribute%2F%40name%3D%27OBS%3AMaintained%27%29"
    assert_response :success
    ret = ActiveXML::XMLNode.new @response.body
    assert_equal ret.package.each.count, 3
   
    # do the real mbranch for default maintained packages
    prepare_request_with_user "tom", "thunder"
    post "/source", :cmd => "branch", :package => "pack2", :noaccess => 1
    assert_response :success
    get "/source/home:tom:branches:OBS_Maintained:pack2/_meta"
    assert_response :success
    assert_tag( :parent => {:tag => "access"}, :tag => "disable", :content => nil )
    delete "/source/home:tom:branches:OBS_Maintained:pack2"
    assert_response :success
    post "/source", :cmd => "branch", :package => "pack2"
    assert_response :success

    # validate result
    get "/source/home:tom:branches:OBS_Maintained:pack2"
    assert_response :success
    get "/source/home:tom:branches:OBS_Maintained:pack2/_meta"
    assert_response :success
    assert_no_tag( :parent => {:tag => "access"}, :tag => "disable", :content => nil )
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack2.BaseDistro2.0/_meta"
    assert_response :success
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack2.BaseDistro/_meta"
    assert_response :success
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack2.BaseDistro2.0/_link"
    assert_response :success

    assert_tag :tag => "link", :attributes => { :project => "BaseDistro2.0:LinkedUpdateProject", :package => "pack2" }
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack2.BaseDistro/_link"
    assert_response :success
    assert_tag :tag => "link", :attributes => { :project => "BaseDistro:Update", :package => "pack2" }
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack2.BaseDistro/_history"
    assert_response :success
    assert_tag :tag => "comment", :content => "fetch updates from devel package"
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack2.BaseDistro3/_link"
    assert_response :success
    assert_tag :tag => "link", :attributes => { :project => "BaseDistro3", :package => "pack2" }
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack2_linked.BaseDistro2.0/_link"
    assert_response :success
    assert_no_tag :tag => "link", :attributes => { :project => "BaseDistro2.0" }
    assert_tag :tag => "link", :attributes => { :package => "pack2.BaseDistro2.0" }

    # test branching another package set into same project
    post "/source", :cmd => "branch", :package => "pack1", :target_project => "home:tom:branches:OBS_Maintained:pack2"
    assert_response :success
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack1.BaseDistro"
    assert_response :success

    # test branching another package set into same project from same project
    post "/source", :cmd => "branch", :package => "pack3", :target_project => "home:tom:branches:OBS_Maintained:pack2"
    assert_response :success
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack3.BaseDistro"
    assert_response :success
    # test branching another package only reachable via project link into same project
    post "/source", :cmd => "branch", :package => "kdelibs", :target_project => "home:tom:branches:OBS_Maintained:pack2", :noaccess => 1
    assert_response 403
    assert_tag :tag => "status", :attributes => { :code => "create_project_no_permission" }

#FIXME: backend has a bug that it destroys the link even with keeplink if opackage has no rev
    put "/source/home:coolo:test/kdelibs_DEVEL_package/DUMMY", "CONTENT"
    assert_response :success

    post "/source", :cmd => "branch", :package => "kdelibs", :target_project => "home:tom:branches:OBS_Maintained:pack2"
    assert_response :success
    get "/source/home:tom:branches:OBS_Maintained:pack2/kdelibs.kde4/_link"
    assert_response :success
    assert_tag :tag => "link", :attributes => { :project => "kde4", :package => "kdelibs" }

    # do some file changes
    put "/source/home:tom:branches:OBS_Maintained:pack2/kdelibs.kde4/new_file", "new_content_0815"
    assert_response :success
    put "/source/home:tom:branches:OBS_Maintained:pack2/pack3.BaseDistro/new_file", "new_content_2137"
    assert_response :success

    # validate created project meta
    get "/source/home:tom:branches:OBS_Maintained:pack2/_meta"
    assert_response :success
    assert_tag :parent => { :tag => "build" }, :tag => "disable"

    assert_tag :parent => { :tag => "repository", :attributes => { :name => "BaseDistro2.0_BaseDistro2LinkedUpdateProject_repo" } }, 
               :tag => "path", :attributes => { :repository => "BaseDistro2LinkedUpdateProject_repo", :project => "BaseDistro2.0:LinkedUpdateProject" }
    assert_tag :parent => { :tag => "repository", :attributes => { :name => "BaseDistro2.0_BaseDistro2LinkedUpdateProject_repo" } }, 
               :tag => "arch", :content => "i586"

    assert_tag :parent => { :tag => "repository", :attributes => { :name => "BaseDistro_BaseDistroUpdateProject_repo" } }, 
               :tag => "path", :attributes => { :repository => "BaseDistroUpdateProject_repo", :project => "BaseDistro:Update" }

    assert_tag( :tag => "releasetarget", :attributes => { :project => "BaseDistro:Update", :repository => "BaseDistroUpdateProject_repo", :trigger => nil } )

    assert_tag( :tag => "releasetarget", :attributes => { :project => "BaseDistro2.0:LinkedUpdateProject", :repository => "BaseDistro2LinkedUpdateProject_repo", :trigger => nil } )

    # validate created package meta
    get "/source/home:tom:branches:OBS_Maintained:pack2/pack2.BaseDistro2.0/_meta"
    assert_response :success
    assert_tag :tag => "package", :attributes => { :name => "pack2.BaseDistro2.0", :project => "home:tom:branches:OBS_Maintained:pack2" }
    assert_tag :parent => { :tag => "build" }, :tag => "enable", :attributes => { :repository => "BaseDistro2.0_BaseDistro2LinkedUpdateProject_repo" }

    # and branch same package again and expect error
    post "/source", :cmd => "branch", :package => "pack1", :target_project => "home:tom:branches:OBS_Maintained:pack2"
    assert_response 400
    assert_tag :tag => "status", :attributes => { :code => "double_branch_package" }
    assert_match(/branch target package already exists:/, @response.body)

    # create patchinfo
    post "/source/BaseDistro?cmd=createpatchinfo&new_format=1"
    assert_response 403
    post "/source/home:tom:branches:OBS_Maintained:pack2?cmd=createpatchinfo&new_format=1"
    assert_response :success
    assert_tag( :tag => "data", :attributes => { :name => "targetpackage"}, :content => "patchinfo" )
    assert_tag( :tag => "data", :attributes => { :name => "targetproject"}, :content => "home:tom:branches:OBS_Maintained:pack2" )

    # create maintenance request
    # without specifing target, the default target must get found via attribute
    post "/request?cmd=create", '<request>
                                   <action type="maintenance_incident">
                                     <source project="home:tom:branches:OBS_Maintained:pack2" />
                                     <options>
                                       <sourceupdate>cleanup</sourceupdate>
                                     </options>
                                   </action>
                                   <state name="new" />
                                 </request>'
    assert_response :success
    assert_tag( :tag => "target", :attributes => { :project => "My:Maintenance" } )
    node = ActiveXML::XMLNode.new(@response.body)
    assert node.has_attribute?(:id)
    id = node.value(:id)

    # validate that request is diffable (not broken)
    post "/request/#{id}?cmd=diff&view=xml", nil
    assert_response :success
    assert_match(/new_content_2137/, @response.body) # check if our changes are part of the diff
    assert_match(/new_content_0815/, @response.body)

    # store data for later checks
    get "/source/home:tom:branches:OBS_Maintained:pack2/_meta"
    oprojectmeta = ActiveXML::XMLNode.new(@response.body)
    assert_response :success

    # accept request
    prepare_request_with_user "maintenance_coord", "power"
    post "/request/#{id}?cmd=changestate&newstate=accepted"
    assert_response :success

    get "/request/#{id}"
    assert_response :success
    data = REXML::Document.new(@response.body)
    maintenanceProject=data.elements["/request/action/target"].attributes.get_attribute("project").to_s
    assert_not_equal maintenanceProject, "My:Maintenance"

    #validate cleanup
    get "/source/home:tom:branches:OBS_Maintained:pack2"
    assert_response 404

    # validate created project
    get "/source/#{maintenanceProject}/_meta"
    assert_response :success
    assert_tag( :parent => {:tag => "build"}, :tag => "disable", :content => nil )
    node = ActiveXML::XMLNode.new(@response.body)
    assert_not_nil node.repository.element_name
    # repository definition must be the same, except for the maintenance trigger
    node.each_repository do |r|
      assert_not_nil r.releasetarget
      assert_equal r.releasetarget.value("trigger"), "maintenance"
      r.releasetarget.delete_attribute("trigger")
    end
    assert_equal node.repository.dump_xml, oprojectmeta.repository.dump_xml
    assert_equal node.build.dump_xml, oprojectmeta.build.dump_xml

    get "/source/#{maintenanceProject}"
    assert_response :success
    assert_tag( :tag => "directory", :attributes => { :count => "8" } )

    get "/source/#{maintenanceProject}/pack2.BaseDistro2.0/_meta"
    assert_response :success
    assert_tag( :tag => "enable", :parent => {:tag => "build"}, :attributes => { :repository => "BaseDistro2.0_BaseDistro2LinkedUpdateProject_repo" } )
  end

  def test_create_maintenance_incident
    prepare_request_with_user "king", "sunflower"
    put "/source/Temp:Maintenance/_meta", '<project name="Temp:Maintenance" kind="maintenance"> 
                                             <title/> <description/>
                                             <person userid="maintenance_coord" role="maintainer"/>
                                           </project>'
    assert_response :success

    ActionController::IntegrationTest::reset_auth 
    post "/source/Temp:Maintenance", :cmd => "createmaintenanceincident"
    assert_response 401

    prepare_request_with_user "adrian", "so_alone"
    post "/source/Temp:Maintenance", :cmd => "createmaintenanceincident"
    assert_response 403
    post "/source/home:adrian", :cmd => "createmaintenanceincident"
    assert_response 400
    assert_tag :tag => "status", :attributes => { :code => "incident_has_no_maintenance_project" }

    prepare_request_with_user "maintenance_coord", "power"
    # create a public maintenance incident
    post "/source/Temp:Maintenance", :cmd => "createmaintenanceincident"
    assert_response :success
    assert_tag( :tag => "data", :attributes => { :name => "targetproject" } )
    data = REXML::Document.new(@response.body)
    maintenanceProject=data.elements["/status/data"].text
    incidentID=maintenanceProject.gsub( /^Temp:Maintenance:/, "" )
    get "/source/#{maintenanceProject}/_meta"
    assert_tag( :tag => "project", :attributes => { :kind => "maintenance_incident" } )
    assert_tag( :parent => {:tag => "build"}, :tag => "disable", :content => nil )
    assert_no_tag( :parent => {:tag => "access"}, :tag => "disable", :content => nil )
    assert_tag( :attributes => {:role => "maintainer", :userid => "maintenance_coord"}, :tag => "person", :content => nil )

    # create a maintenance incident under embargo
    post "/source/Temp:Maintenance?cmd=createmaintenanceincident&noaccess=1", nil
    assert_response :success
    assert_tag( :tag => "data", :attributes => { :name => "targetproject" } )
    data = REXML::Document.new(@response.body)
    maintenanceProject2=data.elements["/status/data"].text
    incidentID2=maintenanceProject2.gsub( /^Temp:Maintenance:/, "" )
    get "/source/#{maintenanceProject2}/_meta"
    assert_tag( :parent => {:tag => "build"}, :tag => "disable", :content => nil )
    assert_tag( :parent => {:tag => "access"}, :tag => "disable", :content => nil )
    assert_tag( :attributes => {:role => "maintainer", :userid => "maintenance_coord"}, :tag => "person", :content => nil )

    # cleanup
    delete "/source/Temp:Maintenance"
    assert_response 400
    assert_tag :tag => "status", :attributes => { :code => "delete_error" }
    assert_match(/This maintenance project has incident projects/, @response.body)
    delete "/source/#{maintenanceProject}"
    assert_response :success
    delete "/source/#{maintenanceProject2}"
    assert_response :success
    delete "/source/Temp:Maintenance"
    assert_response :success
  end

  def inject_build_job( project, package, repo, arch )
    job=IO.popen("find #{RAILS_ROOT}/tmp/backend_data/jobs/#{arch}/ -name #{project}::#{repo}::#{package}-*")
    jobfile=job.readlines.first.chomp
    jobid=""
    IO.popen("md5sum #{jobfile}|cut -d' ' -f 1") do |io|
       jobid = io.readlines.first.chomp
    end
    data = REXML::Document.new(File.new(jobfile))
    verifymd5 = data.elements["/buildinfo/verifymd5"].text
    f = File.open("#{jobfile}:status", 'w')
    f.write( "<jobstatus code=\"building\"> <jobid>#{jobid}</jobid> <workerid>simulated</workerid> <hostarch>#{arch}</hostarch> </jobstatus>" )
    f.close
    system("cd #{RAILS_ROOT}/test/fixtures/backend/binary/; exec find . -name '*#{arch}.rpm' -o -name '*src.rpm' -o -name logfile | cpio -H newc -o 2>/dev/null | curl -s -X POST -T - 'http://localhost:3201/putjob?arch=#{arch}&code=success&job=#{jobfile.gsub(/.*\//, '')}&jobid=#{jobid}' > /dev/null")
    system("echo \"#{verifymd5}  #{package}\" > #{jobfile}:dir/meta")
  end

  def run_scheduler( arch )
    perlopts="-I#{RAILS_ROOT}/../backend -I#{RAILS_ROOT}/../backend/build"
    IO.popen("cd #{RAILS_ROOT}/tmp/backend_config; exec perl #{perlopts} ./bs_sched --testmode #{arch}") do |io|
       # just for waiting until scheduler finishes
       io.each {|line| line.strip.chomp unless line.blank? }
    end
  end

  def test_create_maintenance_project_and_release_packages
    prepare_request_with_user "maintenance_coord", "power"

    # setup 'My:Maintenance' as a maintenance project by fetching it's meta and set a type
    get "/source/My:Maintenance/_meta"
    assert_response :success
    maintenance_project_meta = REXML::Document.new(@response.body)
    maintenance_project_meta.elements['/project'].attributes['kind'] = 'maintenance'
    put "/source/My:Maintenance/_meta", maintenance_project_meta.to_s
    assert_response :success

    post "/source/My:Maintenance/_attribute", "<attributes><attribute namespace='OBS' name='MaintenanceIdTemplate'><value>My-%Y-%C</value></attribute></attributes>"
    assert_response :success

    # setup a maintained distro
    post "/source/BaseDistro2.0/_attribute", "<attributes><attribute namespace='OBS' name='Maintained' /></attributes>"
    assert_response :success
    post "/source/BaseDistro2.0/_attribute", "<attributes><attribute namespace='OBS' name='UpdateProject' > <value>BaseDistro2.0:LinkedUpdateProject</value> </attribute> </attributes>"
    assert_response :success
    post "/source/BaseDistro3/_attribute", "<attributes><attribute namespace='OBS' name='Maintained' /></attributes>"
    assert_response :success

    # create a maintenance incident
    post "/source", :cmd => "createmaintenanceincident"
    assert_response :success
    assert_tag( :tag => "data", :attributes => { :name => "targetproject" } )
    data = REXML::Document.new(@response.body)
    maintenanceProject=data.elements["/status/data"].text
    incidentID=maintenanceProject.gsub( /^My:Maintenance:/, "" )
    get "/source/#{maintenanceProject}/_meta"
    assert_response :success
    assert_tag( :parent => {:tag => "build"}, :tag => "disable", :content => nil )
    assert_tag( :tag => "project", :attributes => { :name => maintenanceProject, :kind => "maintenance_incident" } )

    # submit packages via mbranch
    post "/source", :cmd => "branch", :package => "pack2", :target_project => maintenanceProject
    assert_response :success

    # correct branched ?
    get "/source/"+maintenanceProject+"/pack2.BaseDistro2.0/_link"
    assert_response :success
    assert_tag( :tag => "link", :attributes => { :project => "BaseDistro2.0:LinkedUpdateProject", :package => "pack2" } )
    get "/source/"+maintenanceProject
    assert_response :success
    assert_tag( :tag => "directory", :attributes => { :count => "3" } )
    assert_tag( :tag => "entry", :attributes => { :name => "pack2.BaseDistro2.0" } )
    assert_tag( :tag => "entry", :attributes => { :name => "pack2_linked.BaseDistro2.0" } )
    assert_tag( :tag => "entry", :attributes => { :name => "pack2.BaseDistro3" } )
    get "/source/"+maintenanceProject+"/_meta"
    assert_response :success
    assert_tag( :tag => "path", :attributes => { :project => "BaseDistro2.0:LinkedUpdateProject", :repository => "BaseDistro2LinkedUpdateProject_repo" } )
    assert_tag( :tag => "releasetarget", :attributes => { :project => "BaseDistro2.0:LinkedUpdateProject", :repository => "BaseDistro2LinkedUpdateProject_repo", :trigger => "maintenance" } )
    assert_tag( :tag => "releasetarget", :attributes => { :project => "BaseDistro3", :repository => "BaseDistro3_repo", :trigger => "maintenance" } )
    # correct vrev ?
    get "/source/"+maintenanceProject+"/pack2.BaseDistro2.0?expand=1"
    assert_response :success
    assert_tag( :tag => "directory", :attributes => { :vrev => "2.7" } )
    # validate package meta
    get "/source/"+maintenanceProject+"/pack2.BaseDistro2.0/_meta"
    assert_response :success
    assert_tag( :parent => { :tag => "build" }, :tag => "enable", :attributes => { :repository => "BaseDistro2.0_BaseDistro2LinkedUpdateProject_repo"} )
    get "/source/"+maintenanceProject+"/pack2_linked.BaseDistro2.0/_meta"
    assert_response :success
    assert_tag( :parent => { :tag => "build" }, :tag => "enable", :attributes => { :repository => "BaseDistro2.0_BaseDistro2LinkedUpdateProject_repo"} )
    get "/source/"+maintenanceProject+"/pack2.BaseDistro3/_meta"
    assert_response :success
    assert_tag( :parent => { :tag => "build" }, :tag => "enable", :attributes => { :repository => "BaseDistro3_BaseDistro3_repo"} )

    # create some changes, including issue_tracker references
    put "/source/"+maintenanceProject+"/pack2.BaseDistro2.0/dummy_file", "DUMMY bnc#1042 CVE-2009-0815"
    assert_response :success
    post "/source/"+maintenanceProject+"/pack2.BaseDistro2.0?unified=1&cmd=diff&filelimit=0&expand=1"
    assert_response :success
    assert_match /DUMMY bnc#1042 CVE-2009-0815/, @response.body

    # search will find this new and not yet processed incident now.
    get "/search/project", :match => '[repository/releasetarget/@trigger="maintenance"]'
    assert_response :success
    assert_tag :parent => { :tag => "collection" },  :tag => 'project', :attributes => { :name => maintenanceProject } 

    # Create patchinfo informations
    post "/source/#{maintenanceProject}?cmd=createpatchinfo&force=1"
    assert_response :success
    assert_tag( :tag => "data", :attributes => { :name => "targetpackage"}, :content => "patchinfo" )
    assert_tag( :tag => "data", :attributes => { :name => "targetproject"}, :content => maintenanceProject )
    get "/source/#{maintenanceProject}/patchinfo/_patchinfo"
    assert_response :success
    assert_tag( :tag => "patchinfo", :attributes => { :incident => incidentID } )
    # add required informations about the update
    pi = REXML::Document.new( @response.body )
    pi.elements["//category"].text = "security"
    pi.elements["//rating"].text = "low"
    put "/source/#{maintenanceProject}/patchinfo/_patchinfo", pi.to_s
    assert_response :success
    get "/source/#{maintenanceProject}/patchinfo/_meta"
    assert_tag( :parent => {:tag => "build"}, :tag => "enable", :content => nil )

    # add another issue and update patchinfo
    put "/source/"+maintenanceProject+"/pack2.BaseDistro2.0/dummy_file", "DUMMY bnc#1042 CVE-2009-0815 bnc#4201"
    assert_response :success
    post "/source/#{maintenanceProject}/patchinfo?cmd=updatepatchinfo"
    assert_response :success

    ### the backend is now building the packages, injecting results
    # run scheduler once to create job file. x86_64 scheduler gets no work
    run_scheduler("x86_64")
    run_scheduler("i586")
    # upload build result as a worker would do
    inject_build_job( maintenanceProject, "pack2.BaseDistro2.0", "BaseDistro2.0_BaseDistro2LinkedUpdateProject_repo", "x86_64" )
    inject_build_job( maintenanceProject, "pack2_linked.BaseDistro2.0", "BaseDistro2.0_BaseDistro2LinkedUpdateProject_repo", "x86_64" )
    inject_build_job( maintenanceProject, "pack2.BaseDistro2.0", "BaseDistro2.0_BaseDistro2LinkedUpdateProject_repo", "i586" )
    inject_build_job( maintenanceProject, "pack2_linked.BaseDistro2.0", "BaseDistro2.0_BaseDistro2LinkedUpdateProject_repo", "i586" )
    inject_build_job( maintenanceProject, "pack2.BaseDistro3", "BaseDistro3_BaseDistro3_repo", "i586" )
    # collect the job results
    run_scheduler( "x86_64" )
    run_scheduler( "i586" )

    # check updateinfo
    get "/build/#{maintenanceProject}/BaseDistro2.0_BaseDistro2LinkedUpdateProject_repo/i586/patchinfo/updateinfo.xml"
    assert_response :success
    assert_tag :parent => { :tag => "update", :attributes => { :from => "maintenance_coord", :status => "stable",  :type => "security", :version => "1" } }, :tag => "id", :content => nil
    assert_tag :tag => "reference", :attributes => { :href => "https://bugzilla.novell.com/show_bug.cgi?id=1042", :id => "1042",  :type => "bugzilla" } 
    assert_tag :tag => "reference", :attributes => { :href => "https://bugzilla.novell.com/show_bug.cgi?id=4201", :id => "4201",  :type => "bugzilla" } 
    assert_tag :tag => "reference", :attributes => { :href => "http://cve.mitre.org/cgi-bin/cvename.cgi?name=CVE-2009-0815", :id => "CVE-2009-0815",  :type => "cve" } 
    assert_no_tag :tag => "reference", :attributes => { :href => "https://bugzilla.novell.com/show_bug.cgi?id=" } 
    assert_no_tag :tag => "reference", :attributes => { :id => "" }

    # create release request
    post "/request?cmd=create", '<request>
                                   <action type="maintenance_release">
                                     <source project="' + maintenanceProject + '" />
                                   </action>
                                   <state name="new" />
                                 </request>'
    assert_response :success
    assert_no_tag( :tag => "target", :attributes => { :project => "BaseDistro2.0" } ) # BaseDistro2 has an update project, nothing should go to GA project
    assert_no_tag( :tag => "target", :attributes => { :project => "BaseDistro2.0:LinkedUpdateProject", :package => "pack2" } )
    assert_no_tag( :tag => "target", :attributes => { :project => "BaseDistro3", :package => "pack2" } )
    assert_no_tag( :tag => "target", :attributes => { :project => maintenanceProject } )
    assert_tag( :tag => "target", :attributes => { :project => "BaseDistro2.0:LinkedUpdateProject", :package => "pack2." + incidentID } )
    assert_tag( :tag => "target", :attributes => { :project => "BaseDistro2.0:LinkedUpdateProject", :package => "pack2_linked." + incidentID } )
    assert_tag( :tag => "target", :attributes => { :project => "BaseDistro2.0:LinkedUpdateProject", :package => "patchinfo." + incidentID } )
    assert_tag( :tag => "target", :attributes => { :project => "BaseDistro3", :package => "pack2." + incidentID } )
    assert_tag( :tag => "target", :attributes => { :project => "BaseDistro3", :package => "patchinfo." + incidentID } )
    assert_tag( :tag => "review", :attributes => { :by_group => "test_group" } )
    node = ActiveXML::XMLNode.new(@response.body)
    assert node.has_attribute?(:id)
    reqid = node.value(:id)

    # validate that request is diffable (not broken)
    post "/request/#{reqid}?cmd=diff", nil
    assert_response :success

    # source project got locked?
    get "/source/#{maintenanceProject}/_meta"
    assert_response :success
    assert_tag( :parent => { :tag => "lock" }, :tag => "enable" )

    # approve review
    prepare_request_with_user "king", "sunflower"
    post "/request/#{reqid}?cmd=changereviewstate&newstate=accepted&by_group=test_group&comment=blahfasel"
    assert_response :success

    # release packages
    post "/request/#{reqid}?cmd=changestate&newstate=accepted"
    assert_response :success
    run_scheduler( "i586" )

    # validate result
    get "/source/BaseDistro2.0:LinkedUpdateProject/pack2/_link"
    assert_response :success
    assert_tag :tag => "link", :attributes => { :project => nil, :package => "pack2.#{incidentID}" }
    get "/source/BaseDistro2.0:LinkedUpdateProject/pack2?expand=1"
    assert_response :success
    assert_tag( :tag => "directory", :attributes => { :vrev => "2.9" } )
    get "/source/BaseDistro2.0:LinkedUpdateProject/pack2.#{incidentID}"
    assert_response :success
    assert_tag( :tag => "directory", :attributes => { :vrev => "2.9" } )
    get "/source/BaseDistro2.0:LinkedUpdateProject/pack2.#{incidentID}/_link"
    assert_response 404
    get "/source/BaseDistro2.0:LinkedUpdateProject/patchinfo"
    assert_response 404
    get "/source/BaseDistro2.0:LinkedUpdateProject/patchinfo.#{incidentID}"
    assert_response :success
    get "/source/BaseDistro2.0:LinkedUpdateProject/patchinfo.#{incidentID}/_patchinfo"
    assert_response :success
    assert_tag :tag => "patchinfo", :attributes => { :incident => incidentID }
    assert_tag :tag => "packager", :content => "maintenance_coord"
    get "/build/BaseDistro2.0:LinkedUpdateProject/BaseDistro2LinkedUpdateProject_repo/i586"
    assert_response :success
    get "/build/BaseDistro2.0:LinkedUpdateProject/BaseDistro2LinkedUpdateProject_repo/i586/patchinfo.#{incidentID}"
    assert_response :success
    assert_tag :tag => "binary", :attributes => { :filename => "updateinfo.xml" }
    get "/build/BaseDistro2.0:LinkedUpdateProject/BaseDistro2LinkedUpdateProject_repo/i586/patchinfo.#{incidentID}/updateinfo.xml"
    assert_response :success
    # check for changed updateinfoid 
    assert_tag :parent => { :tag => "update", :attributes => { :from => "maintenance_coord", :status => "stable",  :type => "security", :version => "1" } }, :tag => "id", :content => "My-#{Time.now.utc.year.to_s}-1"
    # check :full tree
    get "/build/BaseDistro2.0:LinkedUpdateProject/BaseDistro2LinkedUpdateProject_repo/i586/_repository"
    assert_response :success
    assert_tag :parent => { :tag => "binarylist" },  :tag => 'binary', :attributes => { :filename => "package.rpm" } 

    # no maintenance trigger exists anymore
    get "/source/#{maintenanceProject}/_meta"
    assert_response :success
    assert_no_tag :tag => 'releasetarget', :attributes => { :trigger => "maintenance" } 

    # search will find this incident not anymore
    get "/search/project", :match => '[repository/releasetarget/@trigger="maintenance"]'
    assert_response :success
    assert_no_tag :parent => { :tag => "collection" },  :tag => 'project', :attributes => { :name => maintenanceProject } 

    # revoke a release update
    delete "/source/BaseDistro2.0:LinkedUpdateProject/pack2"
    assert_response :success
    delete "/source/BaseDistro2.0:LinkedUpdateProject/pack2_linked"
    assert_response :success
    delete "/source/BaseDistro2.0:LinkedUpdateProject/pack2.0"
    assert_response :success
    delete "/source/BaseDistro2.0:LinkedUpdateProject/pack2_linked.0"
    assert_response :success
    run_scheduler( "i586" )
    get "/build/BaseDistro2.0:LinkedUpdateProject/BaseDistro2LinkedUpdateProject_repo/i586/_repository"
    assert_response :success
    assert_no_tag :parent => { :tag => "binarylist" },  :tag => 'binary'

    # disable lock and cleanup 
    delete "/source/#{maintenanceProject}"
    assert_response 403
    put "/source/#{maintenanceProject}/_meta", "<project name='#{maintenanceProject}'><title/> <description/> <lock><disable/></lock> </project>" 
    assert_response :success
    delete "/source/#{maintenanceProject}"
    assert_response :success
  end

  def test_create_invalid_submit_request
    prepare_request_with_user "tom", "thunder"
    # without specifing target, the default target must get found via attribute
    post "/request?cmd=create", '<request>
                                   <action type="submit">
                                     <source project="BaseDistro2.0" package="pack2" />
                                     <target project="BaseDistro2.0:LinkedUpdateProject" />
                                   </action>
                                   <state name="new" />
                                 </request>'
    assert_response 400
    assert_tag :tag => "status", :attributes => { :code => "request_rejected" }
    assert_match /is a maintenance release project/, @response.body
  end

  def test_create_invalid_incident_request
    prepare_request_with_user "tom", "thunder"
    # without specifing target, the default target must get found via attribute
    post "/request?cmd=create", '<request>
                                   <action type="maintenance_incident">
                                     <source project="home:tom" />
                                     <target project="home:tom" />
                                   </action>
                                   <state name="new" />
                                 </request>'
    assert_response 400
    assert_tag :tag => "status", :attributes => { :code => "incident_has_no_maintenance_project" }
  end

  def test_create_invalid_release_request
    prepare_request_with_user "tom", "thunder"
    # branch a package with simple branch command (not mbranch)
    post "/source/BaseDistro/pack1", :cmd => :branch
    assert_response :success
    # check source link
    get "/source/home:tom:branches:BaseDistro:Update/pack1/_link"
    assert_response :success
    # remove release target
    get "/source/home:tom:branches:BaseDistro:Update/_meta"
    assert_response :success
    pi = REXML::Document.new( @response.body )
    pi.elements['//repository'].delete_element 'releasetarget'
    put "/source/home:tom:branches:BaseDistro:Update/_meta", pi.to_s
    assert_response :success

    # Run without server side expansion
    prepare_request_with_user "maintenance_coord", "power"
    rq = '<request>
           <action type="maintenance_release">
             <source project="home:tom:branches:BaseDistro:Update" package="pack1" />
             <target project="BaseDistro:Update" package="pack1" />
           </action>
           <state name="new" />
         </request>'
    post "/request?cmd=create", rq
    assert_response 400
    assert_tag :tag => "status", :attributes => { :code => "repository_without_releasetarget" }


    # try with server side request expansion
    rq = '<request>
           <action type="maintenance_release">
             <source project="home:tom:branches:BaseDistro:Update" />
           </action>
           <state name="new" />
         </request>'
    post "/request?cmd=create", rq
    assert_response 400
    assert_tag :tag => "status", :attributes => { :code => "wrong_linked_package_source" }

    # add a release target
    prepare_request_with_user "tom", "thunder"
    get "/source/home:tom:branches:BaseDistro:Update/_meta"
    assert_response :success
    pi = REXML::Document.new( @response.body )
    pi.elements['//repository'].add_element 'releasetarget'
    pi.elements['//releasetarget'].add_attribute REXML::Attribute.new('project', 'BaseDistro:Update')
    pi.elements['//releasetarget'].add_attribute REXML::Attribute.new('repository', 'BaseDistroUpdateProject_repo')
    put "/source/home:tom:branches:BaseDistro:Update/_meta", pi.to_s
    assert_response :success

    # retry
    prepare_request_with_user "maintenance_coord", "power"
    post "/request?cmd=create", rq
    assert_response 400
    assert_tag :tag => "status", :attributes => { :code => "missing_patchinfo" }

    # add required informations about the update
    prepare_request_with_user "tom", "thunder"
    post "/source/home:tom:branches:BaseDistro:Update?cmd=createpatchinfo"
    assert_response :success
    post "/source/home:tom:branches:BaseDistro:Update?cmd=createpatchinfo"
    assert_response 400
    assert_tag :tag => "status", :attributes => { :code => "patchinfo_file_exists" }
    post "/source/home:tom:branches:BaseDistro:Update?cmd=createpatchinfo&force=1"
    assert_response :success

    prepare_request_with_user "maintenance_coord", "power"
    post "/request?cmd=create", rq
    assert_response 400
    assert_tag :tag => "status", :attributes => { :code => "build_not_finished" }

    # remove architecture
    prepare_request_with_user "tom", "thunder"
    pi.elements['//repository'].delete_element 'arch'
    put "/source/home:tom:branches:BaseDistro:Update/_meta", pi.to_s
    assert_response :success

    prepare_request_with_user "maintenance_coord", "power"
    post "/request?cmd=create&ignore_build_state=1", rq
    assert_response 400
    assert_tag :tag => "status", :attributes => { :code => "repository_without_architecture" }

    # add a wrong architecture
    prepare_request_with_user "tom", "thunder"
    pi.elements['//repository'].add_element 'arch'
    pi.elements['//arch'].text = "ppc"
    put "/source/home:tom:branches:BaseDistro:Update/_meta", pi.to_s
    assert_response :success

    prepare_request_with_user "maintenance_coord", "power"
    post "/request?cmd=create&ignore_build_state=1", rq
    assert_response 400
    assert_tag :tag => "status", :attributes => { :code => "architecture_order_missmatch" }

    # cleanup
    prepare_request_with_user "tom", "thunder"
    delete "/source/home:tom:branches:BaseDistro:Update"
    assert_response :success
  end

  def test_try_to_release_without_permissions_binary_permissions
    prepare_request_with_user "tom", "thunder"
    # create project without trigger
    put "/source/home:tom:test/_meta", "<project name='home:tom:test'> <title/> <description/> 
                                         <repository name='dummy'>
                                           <releasetarget project='BaseDistro' repository='BaseDistro_repo' />
                                           <arch>i586</arch>
                                          </repository>
                                        </project>"
    assert_response :success
    # add trigger
    put "/source/home:tom:test/_meta", "<project name='home:tom:test'> <title/> <description/> 
                                         <repository name='dummy'>
                                           <releasetarget project='BaseDistro' repository='BaseDistro_repo' trigger='maintenance' />
                                           <arch>i586</arch>
                                          </repository>
                                        </project>"
    assert_response :success
    get "/source/home:tom:test/_meta"
    assert_response :success
    assert_tag(:tag => "releasetarget", :attributes => { :trigger => "maintenance" })
    # create package
    put "/source/home:tom:test/pack/_meta", "<package name='pack'> <title/> <description/> </package>"
    assert_response :success

    # create release request
    post "/request?cmd=create", '<request>
                                   <action type="maintenance_release">
                                     <source project="home:tom:test" package="pack" />
                                     <target project="home:tom:test" package="pack" />
                                   </action>
                                   <state name="new" />
                                 </request>'
    assert_response :success
    node = ActiveXML::XMLNode.new(@response.body)
    assert node.has_attribute?(:id)
    reqid = node.value(:id)

    # fail ...
    post "/request/#{reqid}?cmd=changestate&newstate=accepted"
    assert_response 403
    assert_tag :tag => "status", :attributes => { :code => "release_target_no_permission" }

    # create another request with same target must be blocked
    post "/request?cmd=create", '<request>
                                   <action type="maintenance_release">
                                     <source project="home:tom:test" package="pack" />
                                     <target project="home:tom:test" package="pack" />
                                   </action>
                                   <state name="new" />
                                 </request>'
    assert_response 400
    assert_tag :tag => "status", :attributes => { :code => "open_release_requests" }

    # disable lock and cleanup 
    put "/source/home:tom:test/_meta", "<project name='home:tom:test'><title/> <description/> <lock><disable/></lock> </project>" 
    assert_response :success
    delete "/source/home:tom:test"
    assert_response :success
  end

  def test_try_to_release_without_permissions_source_permissions
    prepare_request_with_user "tom", "thunder"
    # create project
    put "/source/home:tom:test/_meta", "<project name='home:tom:test'> <title/> <description/> </project>" 
    assert_response :success
    put "/source/home:tom:test/pack/_meta", "<package name='pack'> <title/> <description/> </package>"
    assert_response :success

    # create release request
    post "/request?cmd=create", '<request>
                                   <action type="maintenance_release">
                                     <source project="home:tom:test" package="pack" />
                                     <target project="BaseDistro" package="pack" />
                                   </action>
                                   <state name="new" />
                                 </request>'
    assert_response :success
    node = ActiveXML::XMLNode.new(@response.body)
    assert node.has_attribute?(:id)
    reqid = node.value(:id)

    # fail ...
    post "/request/#{reqid}?cmd=changestate&newstate=accepted"
    assert_response 403
    assert_tag :tag => "status", :attributes => { :code => "post_request_no_permission" }

    # disable lock and cleanup 
    put "/source/home:tom:test/_meta", "<project name='home:tom:test'><title/> <description/> <lock><disable/></lock> </project>" 
    assert_response :success
    delete "/source/home:tom:test"
    assert_response :success
  end

  def test_copy_project_for_release
    # as user
    prepare_request_with_user "tom", "thunder"
    post "/source/CopyOfBaseDistro?cmd=copy&oproject=BaseDistro"
    assert_response 403
    post "/source/home:tom:CopyOfBaseDistro?cmd=copy&oproject=BaseDistro"
    assert_response :success
    get "/source/home:tom:CopyOfBaseDistro/_meta"
    assert_response :success
    assert_no_tag :tag => "path"
    delete "/source/home:tom:CopyOfBaseDistro"
    assert_response :success

    # as admin
    prepare_request_with_user "king", "sunflower"
    post "/source/CopyOfBaseDistro?cmd=copy&oproject=BaseDistro&nodelay=1"
    assert_response :success
    get "/source/CopyOfBaseDistro/_meta"
    assert_response :success
    get "/source/BaseDistro"
    assert_response :success
    opackages = ActiveXML::XMLNode.new(@response.body)
    get "/source/CopyOfBaseDistro"
    assert_response :success
    packages = ActiveXML::XMLNode.new(@response.body)
    assert_equal opackages.dump_xml, packages.dump_xml

    # compare revisions
    get "/source/BaseDistro/pack2/_history"
    assert_response :success
    history = ActiveXML::XMLNode.new(@response.body)
    srcmd5 = history.each_revision.last.srcmd5.text
    version = history.each_revision.last.version.text
    time = history.each_revision.last.time.text
    vrev = history.each_revision.last.vrev
    assert_not_nil srcmd5
    get "/source/CopyOfBaseDistro/pack2/_history"
    assert_response :success
    copyhistory = ActiveXML::XMLNode.new(@response.body)
    copysrcmd5 = copyhistory.each_revision.last.srcmd5.text
    copyversion = copyhistory.each_revision.last.version.text
    copytime = copyhistory.each_revision.last.time.text
    copyrev = copyhistory.each_revision.last.rev
    copyvrev = copyhistory.each_revision.last.vrev
    assert_equal srcmd5, copysrcmd5
    assert_equal vrev.to_i, copyvrev.to_i - 1  #the copy gets always an additional commit
    assert_equal version, copyversion
    assert_not_equal time, copytime
    assert_equal copyhistory.each_revision.last.user.text, "king"

    delete "/source/CopyOfBaseDistro"
    assert_response :success
  end

  def test_copy_project_with_history_and_binaries
    prepare_request_with_user "tom", "thunder"
    post "/source/home:tom:CopyOfBaseDistro?cmd=copy&oproject=BaseDistro&withhistory=1"
    assert_response 403
    assert_tag :tag => "status", :attributes => { :code => "project_copy_no_permission" }
    post "/source/home:tom:CopyOfBaseDistro?cmd=copy&oproject=BaseDistro&withbinaries=1"
    assert_response 403
    assert_tag :tag => "status", :attributes => { :code => "project_copy_no_permission" }

    # as admin
    prepare_request_with_user "king", "sunflower"
    post "/source/CopyOfBaseDistro?cmd=copy&oproject=BaseDistro&withhistory=1&withbinaries=1&nodelay=1"
    assert_response :success
    get "/source/CopyOfBaseDistro/_meta"
    assert_response :success
    get "/source/BaseDistro"
    assert_response :success
    opackages = ActiveXML::XMLNode.new(@response.body)
    get "/source/CopyOfBaseDistro"
    assert_response :success
    packages = ActiveXML::XMLNode.new(@response.body)
    assert_equal opackages.to_s, packages.to_s

    # compare revisions
    get "/source/BaseDistro/pack2/_history"
    assert_response :success
    history = ActiveXML::XMLNode.new(@response.body)
    srcmd5 = history.each_revision.last.srcmd5.text
    version = history.each_revision.last.version.text
    time = history.each_revision.last.time.text
    vrev = history.each_revision.last.vrev
    assert_not_nil srcmd5
    get "/source/CopyOfBaseDistro/pack2/_history"
    assert_response :success
    copyhistory = ActiveXML::XMLNode.new(@response.body)
    copysrcmd5 = copyhistory.each_revision.last.srcmd5.text
    copyversion = copyhistory.each_revision.last.version.text
    copytime = copyhistory.each_revision.last.time.text
    copyrev = copyhistory.each_revision.last.rev
    copyvrev = copyhistory.each_revision.last.vrev
    assert_equal srcmd5, copysrcmd5
    assert_equal vrev.to_i + 1, copyvrev.to_i  #the copy gets always a higher vrev
    assert_equal version, copyversion
    assert_not_equal time, copytime
    assert_equal copyhistory.each_revision.last.user.text, "king"

    # compare binaries
    run_scheduler("i586")
    get "/build/BaseDistro/BaseDistro_repo/i586/pack2"
    assert_response :success
    assert_tag :tag => "binary", :attributes => { :filename => "package-1.0-1.i586.rpm" }
    orig = @response.body
    get "/build/CopyOfBaseDistro/BaseDistro_repo/i586/pack2"
    assert_response :success
    assert_equal orig, @response.body

    delete "/source/CopyOfBaseDistro"
    assert_response :success
  end

  def test_copy_project_for_release_with_history
    # this is changing also the source project
    prepare_request_with_user "tom", "thunder"
    post "/source/home:tom:CopyOfBaseDistro?cmd=copy&oproject=BaseDistro&makeolder=1"
    assert_response 403
    assert_tag :tag => "status", :attributes => { :code => "cmd_execution_no_permission" }
    assert_match /requires modification permission in oproject/, @response.body

    # store revisions before copy
    get "/source/BaseDistro/pack2/_history"
    assert_response :success
    originhistory = ActiveXML::XMLNode.new(@response.body)
    originsrcmd5 = originhistory.each_revision.last.srcmd5.text
    originversion = originhistory.each_revision.last.version.text
    origintime = originhistory.each_revision.last.time.text
    originvrev = originhistory.each_revision.last.vrev
    assert_not_nil originsrcmd5

    # as admin
    prepare_request_with_user "king", "sunflower"
    post "/source/CopyOfBaseDistro?cmd=copy&oproject=BaseDistro&withhistory=1&makeolder=1&nodelay=1"
    assert_response :success
    get "/source/CopyOfBaseDistro/_meta"
    assert_response :success
    get "/source/BaseDistro"
    assert_response :success
    opackages = ActiveXML::XMLNode.new(@response.body)
    get "/source/CopyOfBaseDistro"
    assert_response :success
    packages = ActiveXML::XMLNode.new(@response.body)
    assert_equal opackages.to_s, packages.to_s

    # compare revisions of source project
    get "/source/BaseDistro/pack2/_history"
    assert_response :success
    history = ActiveXML::XMLNode.new(@response.body)
    srcmd5 = history.each_revision.last.srcmd5.text
    version = history.each_revision.last.version.text
    time = history.each_revision.last.time.text
    rev = history.each_revision.last.rev
    vrev = history.each_revision.last.vrev
    assert_not_nil srcmd5
    assert_equal originsrcmd5, srcmd5
    assert_equal originvrev.to_i + 2, vrev.to_i  # vrev jumps two numbers
    assert_equal version, originversion
    assert_not_equal time, origintime
    assert_equal "king", history.each_revision.last.user.text

    # compare revisions of destination project
    get "/source/CopyOfBaseDistro/pack2/_history"
    assert_response :success
    copyhistory = ActiveXML::XMLNode.new(@response.body)
    copysrcmd5 = copyhistory.each_revision.last.srcmd5.text
    copyversion = copyhistory.each_revision.last.version.text
    copytime = copyhistory.each_revision.last.time.text
    copyrev = copyhistory.each_revision.last.rev
    copyvrev = copyhistory.each_revision.last.vrev
    assert_equal originsrcmd5, copysrcmd5
    expectedvrev="#{(originvrev.to_i+1).to_s}.1" # the copy gets incremented by one, but also extended to avoid that it can become
    assert_equal expectedvrev, copyvrev    # newer than the origin project at any time later.
    assert_equal originversion, copyversion
    assert_not_equal origintime, copytime
    assert_equal "king", copyhistory.each_revision.last.user.text

    #cleanup
    delete "/source/CopyOfBaseDistro"
    assert_response :success
  end

end
