require "test_helper"

class GoalFundingHelperTest < ActionView::TestCase
  test "cash previews show every saved fractional digit" do
    I18n.with_locale(:en) do
      assert_equal "$0.0001", funding_money("0.0001", "USD")
      assert_equal "$150.0001", funding_money("150.0001", "USD")
      assert_equal "$150.25", funding_money("150.2500", "USD")
      assert_equal "$150.00", funding_money("150", "USD")
    end
  end
end
