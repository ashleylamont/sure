class GoalFundingController < ApplicationController
  before_action :require_preview_features!
  before_action :set_funding

  rescue_from Goal::AllocationError do |error|
    redirect_to goal_funding_path, alert: error.message
  end
  rescue_from ActiveRecord::RecordInvalid do |error|
    redirect_to goal_funding_path, alert: error.record.errors.full_messages.to_sentence
  end

  def index
    @accounts = @funding.accounts.to_a
    @plans = @funding.plans
    @goals = @funding.goals.to_a
    history = GoalAllocationChange.joins(:goal_allocation).where(goal_allocations: { family_id: Current.family.id })
    visible = history.where(account_id: @accounts.map(&:id))
    deleted = history.where(goal_allocations: { user_id: Current.user.id }).where.not(account_id: Account.select(:id))
    @history = visible.or(deleted).includes(goal_allocation: :allocation_changes).order(created_at: :desc, id: :desc).limit(50)
  end

  private
    def set_funding
      @funding = Goal::Funding.new(Current.user)
    end
end
