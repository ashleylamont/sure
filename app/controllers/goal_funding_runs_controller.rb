class GoalFundingRunsController < GoalFundingController
  def show
    @run = @funding.run(params[:id])
    @plan = @run.goal_funding_plan
    @reversing = params[:operation] == "reverse"
    @preview = @reversing ? @run.reversal_preview(actor: Current.user) : @plan.preview(entry: @run.source_entry, run: @run)
  end

  def retry
    run = @funding.run(params[:id]).retry_with_preview!(actor: Current.user, preview_token: params[:preview_token])
    redirect_to goal_funding_run_path(run), notice: t("goal_funding.run_reviewed")
  end

  def skip
    run = @funding.run(params[:id]).skip!(actor: Current.user)
    redirect_to goal_funding_run_path(run), notice: t("goal_funding.run_reviewed")
  end

  def reverse
    run = @funding.run(params[:id]).reverse!(actor: Current.user, preview_token: params[:preview_token])
    redirect_to goal_funding_run_path(run), notice: t("goal_funding.run_reviewed")
  end
end
