require 'api_exception'

class Review < ActiveRecord::Base

  class NotFoundError < APIException
    setup 'review_not_found', 404, "Review not found"
  end

  belongs_to :bs_request
  validates_inclusion_of :state, :in => VALID_REQUEST_STATES
  
  before_validation(on: :create) do
    if read_attribute(:state).nil?	
      self.state = :new
    end
  end

  def state
    read_attribute(:state).to_sym
  end

  def self.new_from_xml_hash(hash)
    r = Review.new

    r.state = hash.delete("state") { raise ArgumentError, "no state" }
    r.state = r.state.to_sym

    r.by_user = hash.delete("by_user")
    r.by_group = hash.delete("by_group")
    r.by_project = hash.delete("by_project")
    r.by_package = hash.delete("by_package")

    r.reviewer = r.creator = hash.delete("who")
    r.reason = hash.delete("comment")
    begin
      r.created_at = Time.zone.parse(hash.delete("when"))
    rescue TypeError
      # no valid time -> ignore
    end

    raise ArgumentError, "too much information #{hash.inspect}" unless hash.blank?
    r
  end

  def _get_attributes
    attributes = { :state => self.state.to_s  }
    # old requests didn't have who and when
    attributes[:when] = self.created_at.strftime("%Y-%m-%dT%H:%M:%S") if self.reviewer
    attributes[:who] = self.reviewer if self.reviewer
    attributes[:by_group] = self.by_group if self.by_group
    attributes[:by_user] = self.by_user if self.by_user
    attributes[:by_package] = self.by_package if self.by_package
    attributes[:by_project] = self.by_project if self.by_project

    attributes
  end

  def render_xml(builder)
    builder.review(_get_attributes) do
      builder.comment! self.reason if self.reason
    end
  end

  def webui_infos
    ret = _get_attributes
    # XML has this perl format, don't use that here
    ret[:when] = self.created_at
    ret
  end

  def create_notification_event(params = {})
    params[:comment] = self.reason
    if self.by_package
      params[:newreviewer_project] = self.by_project
      params[:newreviewer_package] = self.by_package
      Event::RequestReviewerPackageAdded.create params
    elsif self.by_project
      params[:newreviewer_project] = self.by_project
      Event::RequestReviewerProjectAdded.create params
    elsif self.by_user
      params[:newreviewer] = self.by_user
      Event::RequestReviewerAdded.create params
    elsif self.by_group
      params[:newreviewer_group] = self.by_group
      Event::RequestReviewerGroupAdded.create params
    end
  end
end
