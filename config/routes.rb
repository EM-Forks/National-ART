Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  devise_for :users
  get '/location', controller: 'sessions', action: 'location'
  post '/location', controller: 'sessions', action: 'location'
	root "people#index"
end
