class RecoverGoalFundingJob < ApplicationJob
  queue_as :scheduled

  def perform(after_id: nil, phase: "plans")
    if phase == "sources"
      scope = GoalFundingRun.where.not(applied_at: nil).where(reversed_at: nil).order(:id)
      scope = scope.where("id > ?", after_id) if after_id
      runs = scope.limit(100).to_a
      runs.each(&:check_source!)
      self.class.perform_later(after_id: runs.last.id, phase: "sources") if runs.size == 100
      return
    end

    scope = GoalFundingPlan.enabled.order(:id)
    scope = scope.where("id > ?", after_id) if after_id
    plans = scope.limit(100).to_a
    plans.each(&:recover!)
    if plans.size == 100
      self.class.perform_later(after_id: plans.last.id)
    else
      self.class.perform_later(phase: "sources")
    end
  end
end
