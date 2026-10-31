class GoalFundingRule < ApplicationRecord
  belongs_to :goal_funding_plan, inverse_of: :rules
  belongs_to :goal, optional: true
  validates :amount, numericality: { greater_than: 0 }
  validates :goal, presence: true

  def snapshot
    reason = "goal_not_fundable" unless goal&.active? && goal.currency == goal_funding_plan.currency
    links = goal ? goal.goal_accounts.to_a : []
    backing = links.find { |link| link.account_id == goal_funding_plan.backing_account_id }
    unless backing && links.all? { |link| link.allocated_amount && link.account.currency == goal_funding_plan.currency }
      reason ||= "whole_account_conversion_required"
    end
    total = links.sum(0.to_d) { |link| link.allocated_amount.to_d }
    contribution = stop_at_target? && reason.nil? ? [ amount, [ goal.target_amount - total, 0.to_d ].max ].min : amount
    { "goal_id" => goal_id, "goal_name" => goal&.name, "amount" => contribution.to_s("F"),
      "currency" => goal_funding_plan.currency,
      "configured_amount" => amount.to_s("F"), "stop_at_target" => stop_at_target?, "review_reason" => reason }
  end
end
