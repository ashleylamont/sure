class Api::V1::GoalsController < Api::V1::GoalFundingBaseController
  def index
    render json: { goals: @funding.goals.limit(100).map { |goal| @funding.goal_json(goal) },
                   accounts: @funding.accounts.limit(100).map { |account| Goal::CashReservation.new(account, user: current_resource_owner).as_json } }
  end

  def show
    render json: @funding.goal_json(@funding.goal(params[:id]))
  end

  def create
    save_goal(nil)
  end

  def update
    save_goal(@funding.goal(params[:id], write: true))
  end

  def destroy
    goal = @funding.goal(params[:id], write: true)
    Goal::AllocationAdjustment.with_account_locks(goal.goal_accounts.pluck(:account_id)) do
      goal.lock!
      raise Goal::AllocationError.new(:stale_state, status: :conflict) unless params[:version] == goal.updated_at.iso8601(6)
      goal.destroy!
    end
    head :no_content
  end

  private
    def save_goal(goal)
      data = params.require(:goal).permit(*Goal::Configuration::FIELDS, :version, :idempotency_key, :reason,
        versions: {}, allocations: [ :account_id, :amount, :mode ]).to_h
      saved = Goal::Configuration.new(current_resource_owner, goal).save!(attributes: data,
        allocations: data["allocations"], versions: data["versions"] || {},
        idempotency_key: data["idempotency_key"], reason: data["reason"], version: data["version"])
      render json: @funding.goal_json(saved), status: goal ? :ok : :created
    end
end
