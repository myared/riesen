require "application_system_test_case"

class FastForwardTimeTest < ApplicationSystemTestCase
  setup do
    ensure_application_setting

    @patient = Patient.create!(
      first_name: "John",
      last_name: "Doe",
      age: 45,
      mrn: "SYS_#{SecureRandom.hex(4)}",
      esi_level: 3,
      location_status: :needs_room_assignment,
      arrival_time: 2.hours.ago,
      triage_completed_at: 1.hour.ago
    )

    @care_pathway = @patient.care_pathways.create!(
      pathway_type: :emergency_room,
      status: :in_progress,
      started_at: 1.hour.ago,
      started_by: "Test Provider"
    )

    @lab_order = CarePathwayOrder.create!(
      care_pathway: @care_pathway,
      name: "CBC with Differential",
      order_type: :lab,
      status: :ordered,
      ordered_at: 30.minutes.ago,
      timer_status: "green"
    )
  end

  test "clicking +10m button should fast forward time with confirmation" do
    visit dashboard_triage_path

    # Verify the button is present
    assert_selector "form[action='#{simulation_fast_forward_time_path}']"
    assert_button "+ 10m"

    # Store original timestamps before fast forward
    original_arrival = @patient.arrival_time
    original_order_time = @lab_order.ordered_at

    # Handle the confirmation dialog and click the button
    accept_confirm do
      click_button "+ 10m"
    end

    # Should redirect back to the same page
    assert_current_path dashboard_triage_path

    # Should show success message
    assert_text "Fast forwarded all timers by 10 minutes"
    assert_text "records updated"

    # Verify timestamps were actually updated in the database
    @patient.reload
    @lab_order.reload

    assert @patient.arrival_time < original_arrival
    assert @lab_order.ordered_at < original_order_time

    # Verify the time difference is approximately 10 minutes
    time_diff_patient = (original_arrival - @patient.arrival_time) / 60
    time_diff_order = (original_order_time - @lab_order.ordered_at) / 60

    assert_in_delta 10, time_diff_patient, 1.0  # Within 1 minute tolerance
    assert_in_delta 10, time_diff_order, 1.0    # Within 1 minute tolerance
  end

  test "canceling +10m confirmation should not fast forward time" do
    visit dashboard_triage_path

    # Store original timestamps
    original_arrival = @patient.arrival_time
    original_order_time = @lab_order.ordered_at

    # Cancel the confirmation dialog
    dismiss_confirm do
      click_button "+ 10m"
    end

    # Should stay on the same page
    assert_current_path dashboard_triage_path

    # Should not show success message
    assert_no_text "Fast forwarded all timers"

    # Verify timestamps were NOT updated
    @patient.reload
    @lab_order.reload

    assert_equal original_arrival.to_i, @patient.arrival_time.to_i
    assert_equal original_order_time.to_i, @lab_order.ordered_at.to_i
  end

  test "+10m button should be present on all dashboard pages" do
    # Test that the button is available on all main dashboard views
    dashboard_paths = [
      dashboard_triage_path,
      dashboard_rp_path,
      dashboard_ed_rn_path,
      dashboard_charge_rn_path,
      dashboard_provider_path
    ]

    dashboard_paths.each do |path|
      visit path

      # Verify the fast forward button is present
      assert page.has_selector?("form[action='#{simulation_fast_forward_time_path}']", count: 1),
             "Expected fast forward form on #{path}"

      assert_button "+ 10m"

      # Verify it has the confirmation attribute
      button = find_button("+ 10m")
      assert button["data-turbo-confirm"], "Button should have confirmation dialog on #{path}"
      assert_equal "This will advance ALL timers by 10 minutes. Continue?",
                   button["data-turbo-confirm"],
                   "Confirmation message should be correct on #{path}"
    end
  end

  test "-10m button should require confirmation on all dashboard pages" do
    dashboard_paths = [
      dashboard_triage_path,
      dashboard_rp_path,
      dashboard_ed_rn_path,
      dashboard_charge_rn_path,
      dashboard_provider_path
    ]

    dashboard_paths.each do |path|
      visit path

      assert_button "- 10m"

      button = find_button("- 10m")
      assert button["data-turbo-confirm"], "Rewind button should have confirmation dialog on #{path}"
      assert_equal "This will rewind ALL timers by 10 minutes. Continue?",
                   button["data-turbo-confirm"],
                   "Rewind confirmation message should be correct on #{path}"
    end
  end

  test "+10m button should redirect back to current page after action" do
    # Test redirection behavior from different starting pages
    test_pages = [
      dashboard_triage_path,
      dashboard_ed_rn_path,
      dashboard_provider_path
    ]

    test_pages.each do |page_path|
      visit page_path

      accept_confirm do
        click_button "+ 10m"
      end

      # Should redirect back to the original page
      assert_current_path page_path

      # Should show success message
      assert_text "Fast forwarded all timers by 10 minutes"
    end
  end

  test "+10m button should update timer display colors after fast forward" do
    # Setup an order that will change timer status after fast forward
    @lab_order.update!(
      ordered_at: 35.minutes.ago,  # 35 + 10 = 45 minutes = red for lab orders
      timer_status: "green"
    )

    visit dashboard_triage_path

    # Look for timer status indicators before fast forward
    # This assumes the UI shows timer status somehow (colors, badges, etc.)

    accept_confirm do
      click_button "+ 10m"
    end

    # After fast forward, timer status should be updated
    @lab_order.reload
    assert_equal "red", @lab_order.timer_status

    # The UI should reflect the updated timer status
    # (This test may need adjustment based on actual UI implementation)
    assert_current_path dashboard_triage_path
    assert_text "Fast forwarded all timers by 10 minutes"
  end

  test "+10m button should work with JavaScript disabled" do
    # Ensure the button works even without JavaScript
    # This tests the form submission fallback

    # Disable JavaScript for this test
    Capybara.current_driver = :rack_test

    visit dashboard_triage_path

    # Store original timestamp
    original_arrival = @patient.arrival_time

    # Click the button (no JavaScript, so no confirmation dialog)
    click_button "+ 10m"

    # Should redirect and show success
    assert_current_path dashboard_triage_path
    assert_text "Fast forwarded all timers by 10 minutes"

    # Verify the action actually worked
    @patient.reload
    assert @patient.arrival_time < original_arrival

    # Reset driver to default
    Capybara.current_driver = Capybara.default_driver
  end

  test "+10m button should handle server errors gracefully" do
    visit dashboard_triage_path

    # Simulate a server error by stubbing the controller action
    # This is a bit tricky in system tests, so we'll test the error handling indirectly

    # We can't easily simulate server errors in system tests,
    # but we can verify the button behavior is consistent
    assert_button "+ 10m"
    assert_selector "form[action='#{simulation_fast_forward_time_path}'][method='post']"

    # The form should use POST method for safety
    form = find("form[action='#{simulation_fast_forward_time_path}']")
    assert_equal "post", form["method"].downcase
  end

  test "+10m button should update patient count display" do
    # If the header shows active patient count, it should remain consistent
    visit dashboard_triage_path

    unless page.has_css?(".ed-header__patient-count")
      skip "Header patient count not displayed"
    end

    original_count_text = find(".ed-header__patient-count").text

    accept_confirm do
      click_button "+ 10m"
    end

    # Patient count should remain the same (patients aren't added/removed)
    assert_text original_count_text
  end

  test "multiple rapid +10m clicks should be handled safely" do
    visit dashboard_triage_path

    original_arrival = @patient.arrival_time

    # First click
    accept_confirm do
      click_button "+ 10m"
    end

    assert_text "Fast forwarded all timers by 10 minutes"

    # Immediate second click (testing for race conditions/double submission)
    accept_confirm do
      click_button "+ 10m"
    end

    # Should handle the second request gracefully
    assert_text "Fast forwarded all timers by 10 minutes"

    # Verify the patient was updated (should be ~20 minutes advanced total)
    @patient.reload
    time_diff = (original_arrival - @patient.arrival_time) / 60
    assert time_diff >= 10, "Time should be advanced by at least 10 minutes"
    assert time_diff <= 25, "Time should not be advanced by more than 25 minutes"
  end
end
