Rails.application.routes.draw do
  root to: redirect('/dashboard/triage')

  namespace :dashboard do
    get "triage"
    get "rp"
    get "ed_rn"
    get "charge_rn"
    get "provider"
  end

  # Settings routes
  get 'settings', to: 'settings#index'
  patch 'settings', to: 'settings#update'
  put 'settings', to: 'settings#update'
  
  resources :patients, only: [:show] do
    member do
      post :add_event
      post :update_vitals
      post :assign_room
      post :add_demo_orders
    end
    
    resources :care_pathways do
      member do
        post 'complete_step/:step_id', to: 'care_pathways#complete_step', as: :complete_step
        post 'add_order', to: 'care_pathways#add_order'
        post 'update_order_status/:order_id', to: 'care_pathways#update_order_status', as: :update_order_status
        post 'add_procedure', to: 'care_pathways#add_procedure'
        post 'complete_procedure/:procedure_id', to: 'care_pathways#complete_procedure', as: :complete_procedure
        post 'add_clinical_endpoint', to: 'care_pathways#add_clinical_endpoint'
        post 'achieve_endpoint/:endpoint_id', to: 'care_pathways#achieve_endpoint', as: :achieve_endpoint
        post 'discharge', to: 'care_pathways#discharge'
      end
    end
  end
  
  post "simulation/add_patient", to: "simulation#add_patient"
  post "simulation/fast_forward_time", to: "simulation#fast_forward_time"
  post "simulation/rewind_time", to: "simulation#rewind_time"
  
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker
end
