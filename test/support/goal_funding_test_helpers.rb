module GoalFundingTestHelpers
  def setup_funding_context
    @user = users(:family_admin)
    @user.update!(preferences: @user.preferences.merge("preview_features_enabled" => true))
    @family = @user.family
    @family.update!(timezone: "UTC")
    travel_to Time.utc(2026, 11, 1, 12)
    @cash = funding_account("Shared savings", 2000)
    @salary_account = funding_account("Salary receiving account", 0)
    @protected_goal = funding_goal("Repayment reserve", 1000, target: 5000)
    @etf = funding_goal("Investment cash", 0, target: 300)
    @giving = funding_goal("Donations", 0, target: 200)
    @sample = salary_entry(date: Date.new(2026, 10, 29))
    Goal::CashReservation.record_reconciliation!(@cash)
  end

  def funding_account(name, balance)
    @family.accounts.create!(owner: @user, name: name, currency: "USD", balance: balance,
                             cash_balance: balance, accountable: Depository.create!, status: "active")
  end

  def funding_goal(name, amount, target: 1000)
    goal = @family.goals.new(name: name, target_amount: target, currency: "USD", kind: "maintained", color: Goal::COLORS.first)
    goal.goal_accounts.build(account: @cash, allocated_amount: amount)
    goal.save!
    goal
  end

  def salary_entry(date: @family.local_date, name: "Payroll credit", amount: -4000, **attributes)
    entry = @salary_account.entries.create!(name: name, date: date, amount: amount, currency: "USD",
                                    entryable: Transaction.new(kind: "standard"), **attributes)
    Goal::CashReservation.record_reconciliation!(@salary_account.reload)
    entry
  end

  def funding_plan(enable: true, rules: nil)
    plan = @family.goal_funding_plans.new(user: @user)
    plan.configure!(actor: @user, attributes: {
      name: "Ordinary salary funding", backing_account_id: @cash.id, sample_entry_id: @sample.id,
      source_name: @sample.name, minimum_salary: "4000", maximum_salary: "4000", effective_on: "2026-11-02"
    }, rules: rules || [ { goal_id: @etf.id, amount: "150" }, { goal_id: @giving.id, amount: "100" } ])
    plan.enable!(actor: @user, preview_token: plan.preview[:preview_token], confirm_salary_source: true) if enable
    plan
  end

  def adjustment(operations, key: SecureRandom.uuid, versions: nil, **options)
    Goal::AllocationAdjustment.new(user: @user, adjustments: operations,
      versions: versions || { @cash.id => @cash.reload.goal_allocation_version }, idempotency_key: key,
      reason: "Reviewed allocation", **options)
  end

  def allocation_for(goal)
    goal.goal_accounts.find_by!(account: @cash).reload.allocated_amount
  end
end
