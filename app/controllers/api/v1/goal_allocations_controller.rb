class Api::V1::GoalAllocationsController < Api::V1::GoalFundingBaseController
  def preview
    render json: adjustment.preview
  end

  def create
    render json: adjustment.apply!
  end

  private
    def adjustment
      data = params.require(:allocation).permit(:idempotency_key, :reason, :preview_token, :confirm_conversion,
        versions: {}, floors: {}, adjustments: [ :goal_id, :account_id, :amount, :mode ]).to_h.symbolize_keys
      Goal::AllocationAdjustment.new(user: current_resource_owner, **data)
    end
end
