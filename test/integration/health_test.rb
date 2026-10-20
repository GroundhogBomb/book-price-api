require "test_helper"

class HealthTest < ActionDispatch::IntegrationTest
  test "up stays available alongside the v1 API" do
    get "/up"
    assert_response :success
  end
end
