# This class represents the communication that took place between OBS and the
# SCM to render each one of the check marks.
#
# Those check marks appear as green, orange and red ticks at the bottom of a
# PR or next to a commit, on GitHub.
#
# The details of the request and the response will be shown in the
# Reports to the SCM tab in Workflow Runs show page.
class ScmStatusReport < ApplicationRecord
  belongs_to :workflow_run

  def pretty_request_parameters
    return unless request_parameters

    JSON.pretty_generate(JSON.parse(request_parameters))
  end
end

# == Schema Information
#
# Table name: scm_status_reports
#
#  id                 :integer          not null, primary key
#  request_parameters :text(4294967295)
#  response_body      :text(4294967295)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  workflow_run_id    :integer
#
