class Assistant::Function::GoalFunding < Assistant::Function
  def strict_mode?
    false
  end

  def params_schema
    build_schema(properties: self.class::PROPERTIES, required: self.class::REQUIRED)
  end

  def call(params = {})
    funding = Goal::Funding.new(user)
    case name
    when "get_goals"
      { goals: funding.goals.limit(100).map { |goal| funding.goal_json(goal) },
        accounts: funding.accounts.limit(100).map { |account| Goal::CashReservation.new(account, user: user).as_json } }
    when "update_goal"
      data = params.fetch("goal")
      goal = Goal::Configuration.new(user, funding.goal(params["goal_id"], write: true)).save!(attributes: data,
        allocations: data["allocations"], versions: data["versions"] || {}, version: data["version"],
        idempotency_key: data["idempotency_key"], reason: data["reason"])
      funding.goal_json(goal)
    when "adjust_goal_allocations"
      values = params.slice("adjustments", "versions", "floors", "idempotency_key", "reason", "preview_token", "confirm_conversion").symbolize_keys
      adjustment = Goal::AllocationAdjustment.new(user: user, **values)
      params["apply"] == true ? adjustment.apply! : adjustment.preview
    when "get_goal_funding_plans"
      { plans: funding.plans.first(100).map { |plan| funding.plan_json(plan) } }
    when "get_goal_funding_runs"
      { runs: funding.runs(funding.plan(params["plan_id"])).map { |run| funding.run_json(run) } }
    when "create_goal_funding_plan", "update_goal_funding_plan"
      values = params.fetch("plan")
      record = funding.save_plan(attributes: values, rules: values["rules"], id: params["plan_id"], revision: params["revision"])
      funding.plan_json(record)
    when "preview_goal_funding_plan"
      funding.plan(params["plan_id"]).preview
    when "enable_goal_funding_plan"
      record = funding.plan(params["plan_id"])
      record.enable!(actor: user, preview_token: params["preview_token"], confirm_salary_source: params["confirm_salary_source"])
      funding.plan_json(record)
    when "disable_goal_funding_plan"
      record = GoalFundingPlan.for_user(user).find(params["plan_id"])
      record.disable!(actor: user)
      { id: record.id, enabled: false }
    when "review_goal_funding_run"
      run = funding.run(params["run_id"])
      case params["operation"]
      when "preview_retry" then return run.goal_funding_plan.preview(entry: run.source_entry, run: run)
      when "preview_reverse" then return run.reversal_preview(actor: user)
      when "retry" then run.retry_with_preview!(actor: user, preview_token: params["preview_token"])
      when "skip" then run.skip!(actor: user)
      when "reverse" then run.reverse!(actor: user, preview_token: params["preview_token"])
      else raise Goal::AllocationError.new(:invalid_adjustment)
      end
      funding.run_json(run)
    end
  rescue Goal::AllocationError => error
    { success: false, error: error.code, message: error.message }
  rescue ActiveRecord::RecordNotFound
    { success: false, error: "not_found" }
  rescue ActiveRecord::RecordInvalid => error
    { success: false, error: "validation_failed", message: error.record.errors.full_messages.to_sentence }
  rescue KeyError, ArgumentError
    { success: false, error: "invalid_parameters" }
  end
end
