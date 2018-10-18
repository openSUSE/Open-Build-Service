class StagingWorkflowPolicy < ApplicationPolicy
  def initialize(user, record)
    raise Pundit::NotAuthorizedError, 'record does not exist' unless record
    @user = user
    @record = record
  end

  def create?
    ProjectPolicy.new(@user, @record.project).update?
  end

  def update?
    create?
  end
end
