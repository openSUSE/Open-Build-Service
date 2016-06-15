module FeaturesAuthentification
  def login(user, password = 'buildservice')
    visit user_login_path
    expect(page).to have_text "Please Log In"
    fill_in 'user_login', with: user.login
    fill_in 'user_password', with: password
    click_button 'Log In »'
    expect(page).to have_link 'link-to-user-home'
  end

  def logout
    visit user_logout_path
    expect(page).to have_no_link('link-to-user-home')
  end
end

RSpec.configure do |c|
  c.include FeaturesAuthentification, type: :feature
end
