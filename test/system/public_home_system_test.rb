require "application_system_test_case"

class PublicHomeSystemTest < ApplicationSystemTestCase
  test "public root presents the threshold question and reveals a response" do
    visit "http://share.lvh.me:4010/"

    assert_selector "h1.threshold-question", text: /Is there\s+a there\s+there\?/
    assert_text "Every destination begins as a rumor."

    click_button "Listen"

    assert_text "There is no directory hiding behind the curtain."
  end
end
