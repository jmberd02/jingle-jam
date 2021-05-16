When("the user visits the homepage") do
  go_to_homepage
end

Then("the main Yogscast twitch should be embedded on the page") do
  expect(page).to have_css("#twitch-embed[data-channel='yogscast'] iframe[src*='.twitch.tv']")
end
