class Goal::AllocationError < StandardError
  attr_reader :code, :details, :status

  def initialize(code, details: {}, status: :unprocessable_entity)
    @code, @details, @status = code.to_s, details, status
    super(I18n.t("goal_funding.errors.#{code}", default: code.to_s.humanize))
  end
end
