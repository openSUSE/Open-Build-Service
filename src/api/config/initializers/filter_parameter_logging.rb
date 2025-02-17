# Be sure to restart your server when you modify this file.

# Configure parameters to be partially matched (e.g. passw matches password) and filtered from the log file.
# Use this to limit dissemination of sensitive information.
# See the ActiveSupport::ParameterFilter documentation for supported notations and behaviors.
# FIXME: `string` is a column from the Tokens table, this column should be renamed.
Rails.application.config.filter_parameters += %i[password passw secret token _key crypt salt certificate otp ssn scm_token string api_key]
