require "application_system_test_case"

class PublicHomeSystemTest < ApplicationSystemTestCase
  test "public root presents the threshold question and reveals a response" do
    visit "http://share.lvh.me:4010/"

    assert_text "Is there a there there?"
    assert_text "If you weren't given a link, you shouldn't be here."

    click_button "Listen"

    assert_text "There is no directory hiding behind the curtain."
  end
end
