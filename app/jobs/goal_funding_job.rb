class GoalFundingJob < ApplicationJob
  queue_as :default

  def self.enqueue(account_id, source_entry_id: nil)
    relevant = GoalFundingPlan.enabled.where(backing_account_id: account_id)
      .or(GoalFundingPlan.enabled.where(source_account_id: account_id)).exists?
    relevant ||= source_entry_id && GoalFundingRun.where(source_entry_id: source_entry_id).exists?
    perform_later(account_id, source_entry_id: source_entry_id) if relevant
  rescue StandardError => error
    # Recovery uses persisted plans and sources; losing an enqueue never replays an allocation.
    DebugLogEntry.capture(category: "goal_funding", level: "warn", message: "Funding evaluation could not be queued; recovery will retry",
                          source: name, account: Account.find_by(id: account_id),
                          metadata: { error_class: error.class.name })
  end

  def perform(account_id, source_entry_id: nil)
    if source_entry_id
      GoalFundingRun.where(source_entry_id: source_entry_id).find_each(&:check_source!)
    end
    account = Account.find_by(id: account_id)
    return unless account

    GoalFundingPlan.enabled.where(family_id: account.family_id)
      .where("source_account_id = :id OR backing_account_id = :id", id: account.id)
      .find_each(&:recover!)
  end
end
