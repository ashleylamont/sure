class Assistant::Function::GetGoals < Assistant::Function::GoalFunding
  PROPERTIES = {}.freeze
  REQUIRED = [].freeze

  def self.name
    "get_goals"
  end

  def self.description
    "Read visible goals, exact reservations, cash shortages and account concurrency versions."
  end
end
