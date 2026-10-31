require "application_system_test_case"
require_relative "../support/goal_funding_test_helpers"

class GoalFundingTest < ApplicationSystemTestCase
  include GoalFundingTestHelpers
  setup do
    setup_funding_context
    @user.update!(show_sidebar: false, show_ai_sidebar: false)
    sign_in @user
  end
  teardown { travel_back }

  test "set aside cash with a preview and configure an explicitly enabled payday plan" do
    visit new_goal_allocation_path(account_id: @cash.id)
    select I18n.t("goal_funding.modes.add"), from: I18n.t("goal_funding.action")
    select @etf.name, from: I18n.t("goal_funding.purpose")
    fill_in I18n.t("goal_funding.amount_in_currency", currency: "USD"), with: "100"
    fill_in I18n.t("goal_funding.reason"), with: "Opening investment reserve"
    click_button I18n.t("goal_funding.preview")
    assert_selector "[aria-label=\"#{I18n.t("goal_funding.changes")}\"]"
    assert_equal 0, allocation_for(@etf)
    click_button I18n.t("goal_funding.apply")
    assert_text I18n.t("goal_funding.saved")
    assert_equal 100, allocation_for(@etf)

    visit new_goal_funding_plan_path
    fill_in I18n.t("goal_funding.name"), with: "Ordinary salary funding"
    select @cash.name, from: I18n.t("goal_funding.backing_account")
    select option_text_for(@sample), from: I18n.t("goal_funding.salary_sample")
    fill_in I18n.t("goal_funding.minimum_salary"), with: "4000"
    fill_in I18n.t("goal_funding.maximum_salary"), with: "4000"
    fill_in I18n.t("goal_funding.contribution_for", name: @etf.name), with: "150"
    fill_in I18n.t("goal_funding.contribution_for", name: @giving.name), with: "100"
    click_button I18n.t("goal_funding.save_draft")
    assert_text "Ordinary salary funding"
    assert_not GoalFundingPlan.find_by!(name: "Ordinary salary funding").enabled?
    check I18n.t("goal_funding.confirm_salary")
    click_button I18n.t("goal_funding.enable")
    assert_text I18n.t("goal_funding.enabled_notice")
    plan = GoalFundingPlan.find_by!(name: "Ordinary salary funding")
    assert plan.enabled?
    travel_to Time.utc(2026, 11, 12, 12)
    salary_entry
    GoalFundingJob.perform_now(@salary_account.id)
    visit goal_funding_plan_path(plan)
    assert_text I18n.t("goal_funding.statuses.applied")
    assert_equal 250, allocation_for(@etf)
    assert_equal 100, allocation_for(@giving)
    page.save_screenshot(Rails.root.join("tmp/goal-funding-plan.png"))
    visit goal_funding_path
    assert_text(/#{Regexp.escape(I18n.t("goal_funding.reserved_now"))}/i)
    page.save_screenshot(Rails.root.join("tmp/goal-funding-reservations.png"))
  end

  private
    def option_text_for(entry)
      find("option[value='#{entry.id}']").text
    end
end
