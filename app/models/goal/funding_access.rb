class Goal::FundingAccess
  def self.accounts(user, write: false)
    raise Goal::AllocationError.new(:forbidden, status: :forbidden) unless user&.active?
    raise Goal::AllocationError.new(:forbidden, status: :forbidden) if write && user.guest?

    scope = user.family.accounts.visible
    write ? scope.writable_by(user) : scope.accessible_by(user)
  end

  def self.goals(user, write: false)
    permitted = accounts(user, write: write).select(:id)
    hidden = GoalAccount.joins(:goal).where(goals: { family_id: user.family_id })
      .where.not(account_id: permitted).select(:goal_id)
    user.family.goals.where.not(id: hidden)
  end

  def self.decimal(value, positive: false)
    number = BigDecimal(value.to_s)
    unless number.finite? && number >= 0 && number <= BigDecimal("999999999999999.9999") && (!positive || number.positive?) && number == number.round(4)
      raise ArgumentError
    end
    number
  rescue ArgumentError, TypeError
    raise Goal::AllocationError.new(:invalid_amount)
  end
end
