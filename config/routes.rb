Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  devise_for :users
  #get '/location', controller: :sessions, action: :location
  get '/location', to: "sessions#location"
  get  '/admin', controller: 'admin', action: 'index'
  get  '/login', controller: 'sessions', action: 'new'
  post '/logout', controller:  'sessions', action:  'destroy'
  get  '/clinic', controller: 'clinic', action: 'index'
  get '/:controller/:action'
  get '/:controller/:action/:id'
  post '/:controller/:action'
  get '/logout', controller: 'sessions', action: 'destroy'
  resource :session
	root "people#index"
end
