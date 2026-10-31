class Api::V1::GoalFundingBaseController < Api::V1::BaseController
  before_action :ensure_funding_access
  before_action :ensure_funding_scope
  before_action :reject_guest_writes!, unless: -> { request.get? || request.head? }

  rescue_from Goal::AllocationError do |error|
    render json: { error: error.code, message: error.message, details: error.details }, status: error.status
  end
  rescue_from ActiveRecord::RecordInvalid do |error|
    render json: { error: "validation_failed", message: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end
  rescue_from ArgumentError, Date::Error do
    render json: { error: "invalid_parameters" }, status: :unprocessable_entity
  end

  private
    def ensure_funding_access
      @funding = Goal::Funding.new(current_resource_owner)
    end

    def ensure_funding_scope
      authorize_scope!(request.get? || request.head? ? :read : :read_write)
    end
end
