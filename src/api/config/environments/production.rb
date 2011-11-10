# Settings specified here will take precedence over those in config/environment.rb

# The production environment is meant for finished, "live" apps.
# Code is not reloaded between requests
config.cache_classes = true

# Use a different logger for distributed setups
# config.logger        = SyslogLogger.new
config.log_level = :info

# Full error reports are disabled and caching is turned on
config.action_controller.consider_all_requests_local = false
config.action_controller.perform_caching             = true

# Enable serving of images, stylesheets, and javascripts from an asset server
# config.action_controller.asset_host                  = "http://assets.example.com"

# Disable delivery errors if you bad email addresses should just be ignored
# config.action_mailer.raise_delivery_errors = false

PROXY_AUTH_MODE = :off

LDAP_MODE = :off
# LDAP Servers separated by ':'.
# OVERRIDE with your company's ldap servers. Servers are picked randomly for
# each connection to distribute load.
LDAP_SERVERS = "ldap1.mycompany.com:ldap2.mycompany.com"
# If you're using LDAP_AUTHENTICATE=:ldap then you should ensure that 
# ldaps is used to transfer the credentials over SSL or use the StartTLS extension
LDAP_SSL = :on
# Use StartTLS extension of LDAP
LDAP_START_TLS = :off
# LDAP port defaults to 636 for ldaps and 389 for ldap and ldap with StartTLS
#LDAP_PORT=
# Authentication with Windows 2003 AD requires
LDAP_REFERRALS = :off

# Max number of times to attempt to contact the LDAP servers
LDAP_MAX_ATTEMPTS = 10

# OVERRIDE with your company's ldap search base for the users who will use OBS
LDAP_SEARCH_BASE = "OU=Organizational Unit,DC=Domain Component"
# Sam Account Name is the login name for LDAP 
LDAP_SEARCH_ATTR = "sAMAccountName"
# The attribute the users name is stored in
LDAP_NAME_ATTR="cn"
# The attribute the users email is stored in
LDAP_MAIL_ATTR="mail"
# Credentials to use to search ldap for the username
LDAP_SEARCH_USER=""
LDAP_SEARCH_AUTH=""

# By default any LDAP user can be used to authenticate to the OBS
# In some deployments this may be too broad and certain criteria should
# be met; eg group membership
#
# To allow only users in a specific group uncomment this line:
#LDAP_USER_FILTER="(memberof=CN=group,OU=Groups,DC=Domain Component)"
#
# Note this is joined to the normal selection like so:
# (&(#{LDAP_SEARCH_ATTR}=#{login})#{LDAP_USER_FILTER})
# giving an ldap search of:
#  (&(sAMAccountName=#{login})(memberof=CN=group,OU=Groups,DC=Domain Component))
#
# Also note that openLDAP must be configured to use the memberOf overlay

# By default any LDAP user can be used to authenticate to the OBS
# In some deployments this may be too broad and certain criteria should
# be met; eg OBS database user table
# This checks the existence of user in OBS database first before query LDAP.
# If the user doesn't exist in OBS database,
# it simply skipped LDAP query.
# If the user exists in OBS database,
# it continues to query LDAP and checks for LDAP username/password.
#LDAP_OBSDB_FILTER = :on

# How to verify:
#   :ldap = attempt to bind to ldap as user using supplied credentials
#   :local = compare the credentials supplied with those in 
#            LDAP using LDAP_AUTH_ATTR & LDAP_AUTH_MECH
#       LDAP_AUTH_MECH can be
#       : md5
#       : cleartext
LDAP_AUTHENTICATE=:ldap
LDAP_AUTH_ATTR="userPassword"
LDAP_AUTH_MECH=:md5

# Whether to update the user info to LDAP server, it does not take effect 
# when LDAP_MODE is not set.
# Since adding new entry operation are more depend on your slapd db define, it might not 
# compatiable with all LDAP server settings, you can use other LDAP client tools for your specific usage
LDAP_UPDATE_SUPPORT = :off
# ObjectClass, used for adding new entry
LDAP_OBJECT_CLASS = ['inetOrgPerson']
# Base dn for the new added entry
LDAP_ENTRY_BASE = "ou=OBSUSERS,dc=EXAMPLE,dc=COM"
# Does sn attribute required, it is a necessary attribute for most of people objectclass,
# used for adding new entry
LDAP_SN_ATTR_REQUIRED = :on

# Whether to search group info from ldap, it does not take effect
# when LDAP_GROUP_SUPPOR is not set.
# Please also set below LDAP_GROUP_* configs correctly to ensure the operation works properly
LDAP_GROUP_SUPPORT = :off
# OVERRIDE with your company's ldap search base for groups
LDAP_GROUP_SEARCH_BASE = "ou=OBSGROUPS,dc=EXAMPLE,dc=COM"
# The attribute the group name is stored in
LDAP_GROUP_TITLE_ATTR = "cn"
# The value of the group objectclass attribute, leave it as "" if objectclass attr doesn't exist
LDAP_GROUP_OBJECTCLASS_ATTR = "groupOfNames"
# Perform the group_user search with the member attribute of group entry or memberof attribute of user entry
# It depends on your ldap define
# The attribute the group member is stored in
LDAP_GROUP_MEMBER_ATTR = "member"
# The attribute the user memberof is stored in
# LDAP_USER_MEMBEROF_ATTR = "memberof"

# Do not allow creating group via API to avoid the conflicts when LDAP_GROUP_SUPPORT is :on
# If you do want to import the group data from LDAP to OBS DB manuallly, please set if to :off
DISALLOW_GROUP_CREATION_WITH_API = :on

SOURCE_HOST = "localhost"
SOURCE_PORT = 5352
SOURCE_PROTOCOL = "http"

EXTENDED_BACKEND_LOG = false

DOWNLOAD_URL='http://localhost:82/'
#YMP_URL='http://software.opensuse.org/ymp'

#require 'hermes'
#Hermes::Config.setup do |hermesconf|
#  hermesconf.dbhost = 'storage'
#  hermesconf.dbuser = 'hermes'
#  hermesconf.dbpass = ''
#  hermesconf.dbname = 'hermes'
#end

RESPONSE_SCHEMA_VALIDATION = true

#require 'memory_debugger'
# dumps the objects after every request
#config.middleware.insert(0, MemoryDebugger)

#require 'memory_dumper'
# dumps the full heap after next request on SIGURG
#config.middleware.insert(0, MemoryDumper)

