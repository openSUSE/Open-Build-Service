puts "Seeding architectures table..."
# NOTE: armvXel is actually obsolete (because it never exist as official platform), but kept for compatibility reasons
["aarch64", "armv4l", "armv5l", "armv6l", "armv7l", "armv5el", "armv6el", "armv7el", "armv8el", "hppa", "i586", "i686", "ia64", "local", "m68k", "mips", "mips32", "mips64", "ppc", "ppc64", "ppc64p7", "ppc64le", "s390", "s390x", "sparc", "sparc64", "sparc64v", "sparcv8", "sparcv9", "sparcv9v", "x86_64"].each do |arch_name|
  Architecture.where(name: arch_name).first_or_create
end
# following our default config
["armv7l", "i586", "x86_64"].each do |arch_name|
  a=Architecture.find_by_name(arch_name)
  a.available=true
  a.recommended=true
  a.save
end

puts "Seeding roles table..."
admin_role      = Role.where(title: "Admin").first_or_create global: true
#user_role       = Role.where(title: "User").first_or_create, global: true
maintainer_role = Role.where(title: "maintainer").first_or_create
bugowner_role   = Role.where(title: "bugowner").first_or_create
reviewer_role   = Role.where(title: "reviewer").first_or_create
downloader_role = Role.where(title: 'downloader').first_or_create
reader_role     = Role.where(title: 'reader').first_or_create

puts "Seeding users table..."
admin  = User.where(login: 'Admin').first_or_create login: 'Admin', email: "root@localhost", realname: "OBS Instance Superuser", state: "2", password: "opensuse", password_confirmation: "opensuse"
User.where(login: '_nobody_').first_or_create login: "_nobody_", email: "nobody@localhost", realname: "Anonymous User", state: "3", password: "123456", password_confirmation: "123456"

puts "Seeding roles_users table..."
RolesUser.where(user_id: admin.id, role_id: admin_role.id).first_or_create

puts "Seeding static_permissions table..."
["status_message_create", "set_download_counters", "download_binaries", "source_access", "access", "global_change_project", "global_create_project", "global_change_package", "global_create_package", "change_project", "create_project", "change_package", "create_package"].each do |sp_title|
  StaticPermission.where(title: sp_title).first_or_create
end

puts "Seeding static permissions for admin role in roles_static_permissions table..."
StaticPermission.all.each do |sp|
  admin_role.static_permissions << sp unless admin_role.static_permissions.find_by_id(sp.id)
end

puts "Seeding static permissions for maintainer role in roles_static_permissions table..."
["change_project", "create_project", "change_package", "create_package"].each do |sp_title|
  sp = StaticPermission.find_by_title(sp_title)
  maintainer_role.static_permissions << sp unless maintainer_role.static_permissions.find_by_id(sp.id)
end

puts "Seeding static permissions for reader role in roles_static_permissions table..."
["access", "source_access"].each do |sp_title|
  sp = StaticPermission.find_by_title(sp_title)
  reader_role.static_permissions << sp unless reader_role.static_permissions.find_by_id(sp.id)
end

puts "Seeding static permissions for downloader role in roles_static_permissions table..."
["download_binaries"].each do |sp_title|
  sp = StaticPermission.find_by_title(sp_title)
  downloader_role.static_permissions << sp unless downloader_role.static_permissions.find_by_id(sp.id)
end

puts "Seeding attrib_namespaces table..."
ans = AttribNamespace.first_or_create name: "OBS"
ans.attrib_namespace_modifiable_bies.first_or_create(bs_user_id: admin.id)

puts "Seeding attrib_types table..."
at = ans.attrib_types.where(name: "VeryImportantProject").first_or_create(value_count: 0)
at.attrib_type_modifiable_bies.where(bs_user_id: admin.id).first_or_create
at = ans.attrib_types.where(name: "UpdateProject").first_or_create(value_count: 1)
at.attrib_type_modifiable_bies.where(bs_user_id: admin.id).first_or_create
at = ans.attrib_types.where(name: "RejectRequests").first_or_create
at.attrib_type_modifiable_bies.where(bs_user_id: admin.id).first_or_create
at = ans.attrib_types.where(name: "ApprovedRequestSource").first_or_create(value_count: 0)
at.attrib_type_modifiable_bies.where(bs_user_id: admin.id).first_or_create
at = ans.attrib_types.where(name: "Maintained").first_or_create(value_count: 0)
at.attrib_type_modifiable_bies.where(bs_user_id: admin.id).first_or_create
at = ans.attrib_types.where(name: "MaintenanceProject").first_or_create(value_count: 0)
at.attrib_type_modifiable_bies.where(bs_user_id: admin.id).first_or_create
at = ans.attrib_types.where(name: "MaintenanceIdTemplate").first_or_create(value_count: 1)
at.attrib_type_modifiable_bies.where(bs_user_id: admin.id).first_or_create
at = ans.attrib_types.where(name: "ScreenShots").first_or_create
at.attrib_type_modifiable_bies.where(bs_user_id: admin.id).first_or_create

at = ans.attrib_types.where(name: "OwnerRootProject").first_or_create
at.attrib_type_modifiable_bies.where(bs_user_id: admin.id).first_or_create
at.allowed_values << AttribAllowedValue.new( value: "DisableDevel" )
at.allowed_values << AttribAllowedValue.new( value: "BugownerOnly" )

at = ans.attrib_types.where(name: "RequestCloned").first_or_create(value_count: 1)
at.attrib_type_modifiable_bies.where(bs_role_id: maintainer_role.id).first_or_create
at = ans.attrib_types.where(name: "ProjectStatusPackageFailComment").first_or_create(value_count: 1)
at.attrib_type_modifiable_bies.where(bs_role_id: maintainer_role.id).first_or_create
at = ans.attrib_types.where(name: "InitializeDevelPackage").first_or_create(value_count: 0)
at.attrib_type_modifiable_bies.where(bs_role_id: maintainer_role.id).first_or_create
at = ans.attrib_types.where(name: "BranchTarget").first_or_create(value_count: 0)
at.attrib_type_modifiable_bies.where(bs_role_id: maintainer_role.id).first_or_create
at = ans.attrib_types.where(name: "BranchRepositoriesFromProject").first_or_create(value_count: 1)
at.attrib_type_modifiable_bies.where(bs_role_id: maintainer_role.id).first_or_create

at = ans.attrib_types.where(name: "Issues").first_or_create(value_count: 0)
at.attrib_type_modifiable_bies.where(bs_role_id: maintainer_role.id).first_or_create
at.attrib_type_modifiable_bies.where(bs_role_id: bugowner_role.id).first_or_create
at.attrib_type_modifiable_bies.where(bs_role_id: reviewer_role.id).first_or_create

at = ans.attrib_types.where(name: "QualityCategory").first_or_create(value_count: 1)
at.attrib_type_modifiable_bies.where(bs_role_id: maintainer_role.id).first_or_create
at.allowed_values << AttribAllowedValue.new( value: "Stable" )
at.allowed_values << AttribAllowedValue.new( value: "Testing" )
at.allowed_values << AttribAllowedValue.new( value: "Development" )
at.allowed_values << AttribAllowedValue.new( value: "Private" )


puts "Seeding db_project_type table by loading test fixtures"
DbProjectType.where(name: "standard").first_or_create
DbProjectType.where(name: "maintenance").first_or_create
DbProjectType.where(name: "maintenance_incident").first_or_create
DbProjectType.where(name: "maintenance_release").first_or_create

# default repository to link when original one got removed
Project.where(name: "deleted").first_or_create do |d|
  d.repositories.new name: "deleted"
end

# set default configuration settings if no settings exist
Configuration.first_or_create(name: "private", title: "Open Build Service") do |conf|
conf.description = <<-EOT
  <p class="description">
    The <a href="http://openbuildservice.org">Open Build Service (OBS)</a>
    is an open and complete distribution development platform that provides a transparent infrastructure for development of Linux distributions, used by openSUSE, MeeGo and other distributions.
    Supporting also Fedora, Debian, Ubuntu, RedHat and other Linux distributions.
  </p>
  <p class="description">
    The OBS is developed under the umbrella of the <a href="http://www.opensuse.org">openSUSE project</a>. Please find further informations on the <a href="http://wiki.opensuse.org/openSUSE:Build_Service">openSUSE Project wiki pages</a>.
  </p>

  <p class="description">
    The Open Build Service developer team is greeting you. In case you use your OBS productive in your facility, please do us a favor and add yourself at <a href="http://wiki.opensuse.org/openSUSE:Build_Service_installations">this wiki page</a>. Have fun and fast build times!
  </p>
EOT
end

puts "Seeding issue trackers ..."
IssueTracker.where(name: 'boost').first_or_create(description: 'Boost Trac', kind: 'trac', regex: 'boost#(\d+)', url: 'https://svn.boost.org/trac/boost/', label: 'boost#@@@', show_url: 'https://svn.boost.org/trac/boost/ticket/@@@')
IssueTracker.where(name: 'bco').first_or_create(description: 'Clutter Project Bugzilla', kind: 'bugzilla', regex: 'bco#(\d+)', url: 'http://bugzilla.clutter-project.org/', label: 'bco#@@@', show_url: 'http://bugzilla.clutter-project.org/show_bug.cgi?id=@@@')
IssueTracker.where(name: 'RT').first_or_create(description: 'CPAN Bugs', kind: 'other', regex: 'RT#(\d+)', url: 'https://rt.cpan.org/', label: 'RT#@@@', show_url: 'http://rt.cpan.org/Public/Bug/Display.html?id=@@@')
IssueTracker.where(name: 'cve').first_or_create(description: 'CVE Numbers', kind: 'cve', regex: '(CVE-\d\d\d\d-\d+)', url: 'http://cve.mitre.org/', label: '@@@', show_url: 'http://cve.mitre.org/cgi-bin/cvename.cgi?name=@@@')
IssueTracker.where(name: 'deb').first_or_create(description: 'Debian Bugzilla', kind: 'bugzilla', regex: 'deb#(\d+)', url: 'http://bugs.debian.org/', label: 'deb#@@@', show_url: 'http://bugs.debian.org/cgi-bin/bugreport.cgi?bug=@@@')
IssueTracker.where(name: 'fdo').first_or_create(description: 'Freedesktop.org Bugzilla', kind: 'bugzilla', regex: 'fdo#(\d+)', url: 'https://bugs.freedesktop.org/', label: 'fdo#@@@', show_url: 'https://bugs.freedesktop.org/show_bug.cgi?id=@@@')
IssueTracker.where(name: 'GCC').first_or_create(description: 'GCC Bugzilla', kind: 'bugzilla', regex: 'GCC#(\d+)', url: 'http://gcc.gnu.org/bugzilla/', label: 'GCC#@@@', show_url: 'http://gcc.gnu.org/bugzilla/show_bug.cgi?id=@@@')
IssueTracker.where(name: 'bgo').first_or_create(description: 'Gnome Bugzilla', kind: 'bugzilla', regex: 'bgo#(\d+)', url: 'https://bugzilla.gnome.org/', label: 'bgo#@@@', show_url: 'https://bugzilla.gnome.org/show_bug.cgi?id=@@@')
IssueTracker.where(name: 'bio').first_or_create(description: 'Icculus.org Bugzilla', kind: 'bugzilla', regex: 'bio#(\d+)', url: 'https://bugzilla.icculus.org/', label: 'bio#@@@', show_url: 'https://bugzilla.icculus.org/show_bug.cgi?id=@@@')
IssueTracker.where(name: 'bko').first_or_create(description: 'Kernel.org Bugzilla', kind: 'bugzilla', regex: '(?:Kernel|K|bko)#(\d+)', url: 'https://bugzilla.kernel.org/', label: 'bko#@@@', show_url: 'https://bugzilla.kernel.org/show_bug.cgi?id=@@@')
IssueTracker.where(name: 'kde').first_or_create(description: 'KDE Bugzilla', kind: 'bugzilla', regex: 'kde#(\d+)', url: 'https://bugs.kde.org/', label: 'kde#@@@', show_url: 'https://bugs.kde.org/show_bug.cgi?id=@@@')
IssueTracker.where(name: 'lp').first_or_create(description: 'Launchpad.net Bugtracker', kind: 'launchpad', regex: 'b?lp#(\d+)', url: 'https://bugs.launchpad.net/bugs/', label: 'lp#@@@', show_url: 'https://bugs.launchpad.net/bugs/@@@')
IssueTracker.where(name: 'Meego').first_or_create(description: 'Meego Bugs', kind: 'bugzilla', regex: 'Meego#(\d+)', url: 'https://bugs.meego.com/', label: 'Meego#@@@', show_url: 'https://bugs.meego.com/show_bug.cgi?id=@@@')
IssueTracker.where(name: 'bmo').first_or_create(description: 'Mozilla Bugzilla', kind: 'bugzilla', regex: 'bmo#(\d+)', url: 'https://bugzilla.mozilla.org/', label: 'bmo#@@@', show_url: 'https://bugzilla.mozilla.org/show_bug.cgi?id=@@@')
IssueTracker.where(name: 'bnc').first_or_create(description: 'Novell Bugzilla', enable_fetch: true, kind: 'bugzilla', regex: '(?:bnc|BNC)\s*[#:]\s*(\d+)', url: 'https://bugzilla.novell.com/', label: 'bnc#@@@', show_url: 'https://bugzilla.novell.com/show_bug.cgi?id=@@@')
IssueTracker.where(name: 'ITS').first_or_create(description: 'OpenLDAP Issue Tracker', kind: 'other', regex: 'ITS#(\d+)', url: 'http://www.openldap.org/its/', label: 'ITS#@@@', show_url: 'http://www.openldap.org/its/index.cgi/Contrib?id=@@@')
IssueTracker.where(name: 'i').first_or_create(description: 'OpenOffice.org Bugzilla', kind: 'bugzilla', regex: 'i#(\d+)', url: 'http://openoffice.org/bugzilla/', label: 'boost#@@@', show_url: 'http://openoffice.org/bugzilla/show_bug.cgi?id=@@@')
IssueTracker.where(name: 'fate').first_or_create(description: 'openSUSE Feature Database', kind: 'fate', regex: '(?:fate|Fate|FATE)\s*#\s*(\d+)', url: 'https://features.opensuse.org/', label: 'fate#@@@', show_url: 'https://features.opensuse.org/@@@')
IssueTracker.where(name: 'rh').first_or_create(description: 'RedHat Bugzilla', kind: 'bugzilla', regex: 'rh#(\d+)', url: 'https://bugzilla.redhat.com/', label: 'rh#@@@', show_url: 'https://bugzilla.redhat.com/show_bug.cgi?id=@@@')
IssueTracker.where(name: 'bso').first_or_create(description: 'Samba Bugzilla', kind: 'bugzilla', regex: 'bso#(\d+)', url: 'https://bugzilla.samba.org/', label: 'bso#@@@', show_url: 'https://bugzilla.samba.org/show_bug.cgi?id=@@@')
IssueTracker.where(name: 'sf').first_or_create(description: 'SourceForge.net Tracker', kind: 'sourceforge', regex: 'sf#(\d+)', url: 'http://sf.net/support/', label: 'sf#@@@', show_url: 'http://sf.net/support/tracker.php?aid=@@@')
IssueTracker.where(name: 'Xamarin').first_or_create(description: 'Xamarin Bugzilla', kind: 'bugzilla', regex: 'Xamarin#(\d+)', url: 'http://bugzilla.xamarin.com/index.cgi', label: 'Xamarin#@@@', show_url: 'http://bugzilla.xamarin.com/show_bug.cgi?id=@@@')
IssueTracker.where(name: 'bxo').first_or_create(description: 'XFCE Bugzilla', kind: 'bugzilla', regex: 'bxo#(\d+)', url: 'https://bugzilla.xfce.org/', label: 'bxo#@@@', show_url: 'https://bugzilla.xfce.org/show_bug.cgi?id=@@@')
