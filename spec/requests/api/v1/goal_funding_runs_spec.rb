require 'swagger_helper'
require Rails.root.join('spec/support/goal_funding_api_context')

RSpec.describe 'Payday funding runs API', type: :request do
  include_context 'goal funding API'
  let(:id) { funding_run.id }
  let(:goal_funding_plan_id) { funding_plan.id }
  path '/api/v1/goal_funding_plans/{goal_funding_plan_id}/goal_funding_runs' do
    parameter name: :goal_funding_plan_id, in: :path, type: :string, required: true
    get 'List the latest funding runs' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      response '200', 'List the latest funding runs' do
        schema({ type: :object, properties: { runs: { type: :array, items: { '$ref' => '#/components/schemas/GoalFundingRunRecord' } } } })
        run_test!
      end
    end
  end
  path '/api/v1/goal_funding_runs/{id}' do
    parameter name: :id, in: :path, type: :string, required: true
    get 'Read a funding run' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      response '200', 'Read a funding run' do
        schema({ '$ref' => '#/components/schemas/GoalFundingRunRecord' })
        run_test!
      end
    end
  end
  path '/api/v1/goal_funding_runs/{id}/preview' do
    parameter name: :id, in: :path, type: :string, required: true
    get 'Preview a retry or compensating reversal' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      parameter name: :operation, in: :query, required: false, schema: { type: :string, enum: %w[retry reverse] }
      response '200', 'Preview a retry or compensating reversal' do
        schema({ type: :object })
        run_test!
      end
    end
  end
  path '/api/v1/goal_funding_runs/{id}/retry' do
    parameter name: :id, in: :path, type: :string, required: true
    post 'Retry using a fresh reviewed preview' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      consumes 'application/json'
      parameter name: :body, in: :body, required: true, schema: { type: :object, required: %w[preview_token], properties: { preview_token: { type: :string } } }
      let(:body) { { preview_token: 'review-required' } }
      response '422', 'Retry using a fresh reviewed preview' do
        schema({ type: :object })
        run_test!
      end
    end
  end
  path '/api/v1/goal_funding_runs/{id}/skip' do
    parameter name: :id, in: :path, type: :string, required: true
    post 'Skip an unapplied run' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      response '200', 'Skip an unapplied run' do
        schema({ '$ref' => '#/components/schemas/GoalFundingRunRecord' })
        run_test!
      end
    end
  end
  path '/api/v1/goal_funding_runs/{id}/reverse' do
    parameter name: :id, in: :path, type: :string, required: true
    post 'Compensate an applied run without moving bank money' do
      tags 'Goal funding'
      security [ { apiKeyAuth: [] } ]
      produces 'application/json'
      consumes 'application/json'
      parameter name: :body, in: :body, required: true, schema: { type: :object, required: %w[preview_token], properties: { preview_token: { type: :string } } }
      let(:body) { { preview_token: 'review-required' } }
      response '422', 'Compensate an applied run without moving bank money' do
        schema({ type: :object })
        run_test!
      end
    end
  end
end
