class Api::V1::GoalFundingRunsController < Api::V1::GoalFundingBaseController
  def index
    plan = @funding.plan(params[:goal_funding_plan_id])
    render json: { runs: @funding.runs(plan).map { |run| @funding.run_json(run) } }
  end

  def show
    render json: @funding.run_json(@funding.run(params[:id]))
  end

  def preview
    run = @funding.run(params[:id])
    render json: params[:operation] == "reverse" ? run.reversal_preview(actor: current_resource_owner) : run.goal_funding_plan.preview(entry: run.source_entry, run: run)
  end

  def retry
    run = @funding.run(params[:id]).retry_with_preview!(actor: current_resource_owner, preview_token: params[:preview_token])
    render json: @funding.run_json(run)
  end

  def skip
    render json: @funding.run_json(@funding.run(params[:id]).skip!(actor: current_resource_owner))
  end

  def reverse
    run = @funding.run(params[:id]).reverse!(actor: current_resource_owner, preview_token: params[:preview_token])
    render json: @funding.run_json(run)
  end
end
