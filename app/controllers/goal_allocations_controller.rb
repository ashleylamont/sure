class GoalAllocationsController < GoalFundingController
  def new
    @accounts = @funding.accounts(write: true).to_a
    @account = params[:account_id].present? ? @accounts.find { |account| account.id == params[:account_id] } : @accounts.first
    raise ActiveRecord::RecordNotFound if params[:account_id].present? && !@account
    @goals = Goal::FundingAccess.goals(Current.user, write: true).where.not(state: Goal::RELEASED_STATES).order(:name)
    @key = SecureRandom.uuid
  end

  def preview
    @data = allocation_params
    @proposal = adjustment.preview
  end

  def create
    adjustment.apply!
    redirect_to goal_funding_path, notice: t("goal_funding.saved")
  end

  private
    def allocation_params
      params.require(:allocation).permit(:account_id, :goal_id, :destination_goal_id, :mode, :amount, :version,
        :idempotency_key, :reason, :preview_token, :confirm_conversion).to_h
    end

    def adjustment
      data = allocation_params
      mode = data.fetch("mode")
      operations = if mode == "floor"
        []
      elsif mode == "move"
        [ { account_id: data["account_id"], goal_id: data["goal_id"], mode: "release", amount: data["amount"] },
          { account_id: data["account_id"], goal_id: data["destination_goal_id"], mode: "add", amount: data["amount"] } ]
      else
        [ { account_id: data["account_id"], goal_id: data["goal_id"], mode: mode, amount: data["amount"] } ]
      end
      Goal::AllocationAdjustment.new(user: Current.user, adjustments: operations,
        versions: { data["account_id"] => data["version"] }, floors: mode == "floor" ? { data["account_id"] => data["amount"] } : {},
        idempotency_key: data["idempotency_key"], reason: data["reason"],
        preview_token: data["preview_token"], confirm_conversion: data["confirm_conversion"])
    end
end
