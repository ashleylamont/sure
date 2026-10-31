class GoalFundingPlansController < GoalFundingController
  def new
    @plan = Current.family.goal_funding_plans.new(user: Current.user, effective_on: Current.family.local_date.next_day)
    prepare_form
  end

  def edit
    @plan = @funding.plan(params[:id])
    prepare_form
  end

  def create
    save_plan
  end

  def update
    save_plan(id: params[:id])
  end

  def show
    @plan = @funding.plan(params[:id])
    @preview = @plan.preview
    @runs = @funding.runs(@plan)
  end

  def enable
    plan = @funding.plan(params[:id])
    plan.enable!(actor: Current.user, preview_token: params[:preview_token], confirm_salary_source: params[:confirm_salary_source])
    redirect_to goal_funding_plan_path(plan), notice: t("goal_funding.enabled_notice")
  end

  def disable
    plan = GoalFundingPlan.for_user(Current.user).find(params[:id])
    plan.disable!(actor: Current.user)
    redirect_to goal_funding_path, notice: t("goal_funding.disabled_notice")
  end

  private
    def prepare_form
      @accounts = @funding.accounts(write: true)
      @goals = Goal::FundingAccess.goals(Current.user, write: true).where(kind: "maintained").order(:name)
      @samples = Entry.where(account_id: Current.user.accessible_accounts.visible.select(:id), entryable_type: "Transaction", excluded: false)
        .where("amount < 0 AND date <= ?", Current.family.local_date).includes(:account, :entryable).order(date: :desc, id: :desc).limit(200)
        .select { |entry| entry.entryable.standard? && !entry.entryable.pending? && !entry.entryable.transfer? }
    end

    def save_plan(id: nil)
      data = params.require(:plan).permit(*GoalFundingPlan::CONFIGURATION_FIELDS, :revision, rules: {}).to_h
      rules = data.fetch("rules", {}).filter_map do |goal_id, values|
        next if values["amount"].blank?
        { goal_id: goal_id, amount: values["amount"], stop_at_target: values["stop_at_target"] }
      end
      @plan = @funding.save_plan(id: id, attributes: data, rules: rules, revision: data["revision"])
      redirect_to goal_funding_plan_path(@plan)
    end
end
