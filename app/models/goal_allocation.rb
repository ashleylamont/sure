class GoalAllocation < ApplicationRecord
  belongs_to :family
  belongs_to :user, optional: true
  has_many :allocation_changes, class_name: "GoalAllocationChange", dependent: :delete_all

  validates :idempotency_key, :payload_fingerprint, :reason, :kind, presence: true

  def self.record_link_change!(link, before:, after:, reason: I18n.t("goal_funding.audit.goal_edit"), metadata: {})
    account = link.account
    actor = Current.user if Current.user&.family_id == account.family_id
    batch = create!(family: account.family, user: actor,
                    idempotency_key: "goal-link:#{link.id}:#{SecureRandom.uuid}",
                    payload_fingerprint: Digest::SHA256.hexdigest([ link.id, before, after ].to_json),
                    kind: "goal_edit", reason: reason, result: metadata)
    batch.allocation_changes.create!(account_id: account.id, goal_id: link.goal_id,
                          account_name: account.name, goal_name: link.goal.name, currency: account.currency,
                          before_amount: before, after_amount: after,
                          delta: before && after ? after - before : nil)
    Account.where(id: account.id).update_all("goal_allocation_version = goal_allocation_version + 1")
    ActiveRecord.after_all_transactions_commit { GoalFundingJob.enqueue(account.id) }
  end

  def readonly?
    persisted?
  end
end
