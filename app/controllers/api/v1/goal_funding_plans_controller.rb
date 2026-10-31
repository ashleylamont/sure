class Api::V1::GoalFundingPlansController < Api::V1::GoalFundingBaseController
  def index
    render json: { plans: @funding.plans.first(100).map { |plan| @funding.plan_json(plan) } }
  end

  def show
    render json: @funding.plan_json(@funding.plan(params[:id]))
  end

  def create
    save_plan
  end

  def update
    save_plan(id: params[:id])
  end

  def preview
    render json: @funding.plan(params[:id]).preview
  end

  def enable
    plan = @funding.plan(params[:id])
    plan.enable!(actor: current_resource_owner, preview_token: params[:preview_token], confirm_salary_source: params[:confirm_salary_source])
    render json: @funding.plan_json(plan)
  end

  def disable
    plan = GoalFundingPlan.for_user(current_resource_owner).find(params[:id])
    plan.disable!(actor: current_resource_owner)
    render json: { id: plan.id, enabled: false }
  end

  private
    def save_plan(id: nil)
      data = params.require(:plan).permit(*GoalFundingPlan::CONFIGURATION_FIELDS, :revision,
        rules: [ :goal_id, :amount, :stop_at_target ]).to_h
      plan = @funding.save_plan(id: id, attributes: data, rules: data["rules"], revision: data["revision"])
      render json: @funding.plan_json(plan), status: id ? :ok : :created
    end
end
