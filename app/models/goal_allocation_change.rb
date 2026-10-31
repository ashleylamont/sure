class GoalAllocationChange < ApplicationRecord
  belongs_to :goal_allocation

  def readonly?
    persisted?
  end
end
