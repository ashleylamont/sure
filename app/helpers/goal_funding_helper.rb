module GoalFundingHelper
  def funding_money(amount, currency)
    amount.nil? ? t("goal_funding.unknown_cash") : Money.new(amount.to_d, currency).format
  end

  def funding_reason(code)
    if code.present?
      t("goal_funding.reasons.#{code}", default: t("goal_funding.errors.#{code}", default: t("goal_funding.reasons.review_required")))
    end
  end

  def funding_goal_name(id, fallback: nil)
    funding_visible_goal_names[id] || fallback || t("goal_funding.private_purpose")
  end

  def funding_sample_label(entry)
    [ l(entry.date), entry.account.name, entry.name, funding_money(entry.amount.abs, entry.currency) ].join(" · ")
  end

  def funding_rule(plan, goal)
    plan.rules.find { |rule| rule.goal_id == goal.id }
  end

  def funding_reserved_label(goal)
    goal.goal_accounts.map do |link|
      amount = link.whole_account? ? t("goal_funding.whole_account") : funding_money(link.allocated_amount, link.account.currency)
      "#{link.account.name}: #{amount}"
    end.join(" · ")
  end

  def funding_remaining_after(preview)
    funding_money([ preview[:account][:unallocated].to_d - preview[:total].to_d, 0 ].max, preview[:account][:currency])
  end

  def funding_managed_account_ids
    @funding_managed_account_ids ||= Current.family.goal_funding_plans.distinct.pluck(:backing_account_id)
  end

  def funding_audit_reason(change)
    ids = change.goal_allocation.allocation_changes.filter_map(&:goal_id)
    hidden = ids - funding_visible_goal_names.keys
    Goal.where(id: hidden).exists? ? t("goal_funding.private_purpose") : change.goal_allocation.reason
  end

  private
    def funding_visible_goal_names
      @funding_visible_goal_names ||= Goal::FundingAccess.goals(Current.user).pluck(:id, :name).to_h
    end
end
