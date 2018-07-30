Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  devise_for :users
  #get '/location', controller: :sessions, action: :location
  get '/location', to: "sessions#location"
  get '/user/programs/:id', to: 'user#programs'
  get  '/admin', controller: 'admin', action: 'index'
  get  '/login', controller: 'sessions', action: 'new'
  post '/logout', controller:  'sessions', action:  'destroy'
  get  '/clinic', controller: 'clinic', action: 'index'
  get '/encounters/new/:encounter_type', controller:  'encounters', action: 'new'
  post '/encounters/new/:encounter_type', controller:  'encounters', action: 'new'
  get '/encounters/new/:encounter_type/:id', controller: 'encounters', action: 'new'
  post '/encounters/new/:encounter_type/:id', controller: 'encounters', action: 'new'
  get '/:controller/:action'
  get '/:controller/:action/:id'
  post '/:controller/:action'
  get '/logout', controller: 'sessions', action: 'destroy'
  get '/people', to: "clinic#index"
  get '/render_date_enrolled_in_art', controller: 'patients', action: 'render_date_enrolled_in_art'
  post '/:controller/:action/:id'

  resources :dispensations, collection: {quantities: :get}
  resources :barcodes, collection: {label: :get}
  resources :relationships, collection: {search: :get}
  resources :encounter_types
  resources :single_sign_on, collection: {get_token: [:get, :post], load_page: [:get, :post],single_sign_in: [:get, :post]}

  resource :session
  #get '/patients/:id', to: 'patients#show'
	root "people#index"
end
