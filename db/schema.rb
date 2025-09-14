# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_09_14_142404) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "care_pathway_clinical_endpoints", force: :cascade do |t|
    t.bigint "care_pathway_id", null: false
    t.string "name", null: false
    t.text "description", null: false
    t.boolean "achieved", default: false
    t.datetime "achieved_at"
    t.string "achieved_by"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["achieved"], name: "index_care_pathway_clinical_endpoints_on_achieved"
    t.index ["care_pathway_id"], name: "index_care_pathway_clinical_endpoints_on_care_pathway_id"
  end

  create_table "care_pathway_orders", force: :cascade do |t|
    t.bigint "care_pathway_id", null: false
    t.string "name", null: false
    t.integer "order_type", null: false
    t.integer "status", default: 0, null: false
    t.datetime "ordered_at"
    t.string "ordered_by"
    t.datetime "status_updated_at"
    t.string "status_updated_by"
    t.text "notes"
    t.jsonb "results"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "collected_at"
    t.datetime "in_lab_at"
    t.datetime "resulted_at"
    t.string "timer_status", default: "green"
    t.integer "last_status_duration_minutes"
    t.datetime "administered_at"
    t.datetime "exam_started_at"
    t.datetime "exam_completed_at"
    t.string "assigned_to"
    t.index ["care_pathway_id"], name: "index_care_pathway_orders_on_care_pathway_id"
    t.index ["order_type"], name: "index_care_pathway_orders_on_order_type"
    t.index ["status"], name: "index_care_pathway_orders_on_status"
    t.index ["timer_status"], name: "index_care_pathway_orders_on_timer_status"
  end

  create_table "care_pathway_procedures", force: :cascade do |t|
    t.bigint "care_pathway_id", null: false
    t.string "name", null: false
    t.text "description"
    t.boolean "completed", default: false
    t.datetime "completed_at"
    t.string "completed_by"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["care_pathway_id"], name: "index_care_pathway_procedures_on_care_pathway_id"
    t.index ["completed"], name: "index_care_pathway_procedures_on_completed"
  end

  create_table "care_pathway_steps", force: :cascade do |t|
    t.bigint "care_pathway_id", null: false
    t.string "name", null: false
    t.integer "sequence", null: false
    t.boolean "completed", default: false
    t.datetime "completed_at"
    t.string "completed_by"
    t.jsonb "data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["care_pathway_id", "sequence"], name: "index_care_pathway_steps_on_care_pathway_id_and_sequence"
    t.index ["care_pathway_id"], name: "index_care_pathway_steps_on_care_pathway_id"
    t.index ["completed"], name: "index_care_pathway_steps_on_completed"
  end

  create_table "care_pathways", force: :cascade do |t|
    t.bigint "patient_id", null: false
    t.integer "pathway_type", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "started_at"
    t.datetime "completed_at"
    t.string "started_by"
    t.string "completed_by"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pathway_type"], name: "index_care_pathways_on_pathway_type"
    t.index ["patient_id"], name: "index_care_pathways_on_patient_id"
    t.index ["status"], name: "index_care_pathways_on_status"
  end

  create_table "events", force: :cascade do |t|
    t.bigint "patient_id", null: false
    t.datetime "time"
    t.string "action"
    t.text "details"
    t.string "performed_by"
    t.string "category"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["patient_id"], name: "index_events_on_patient_id"
  end

  create_table "nursing_tasks", force: :cascade do |t|
    t.bigint "patient_id", null: false
    t.integer "task_type", null: false
    t.string "description", null: false
    t.string "assigned_to"
    t.integer "priority", default: 1
    t.integer "status", default: 0
    t.datetime "due_at"
    t.datetime "completed_at"
    t.string "room_number"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "started_at"
    t.index ["assigned_to"], name: "index_nursing_tasks_on_assigned_to"
    t.index ["patient_id"], name: "index_nursing_tasks_on_patient_id"
    t.index ["priority"], name: "index_nursing_tasks_on_priority"
    t.index ["status"], name: "index_nursing_tasks_on_status"
  end

  create_table "patients", force: :cascade do |t|
    t.string "first_name"
    t.string "last_name"
    t.integer "age"
    t.string "mrn"
    t.string "location"
    t.string "provider"
    t.text "chief_complaint"
    t.integer "esi_level"
    t.integer "pain_score"
    t.datetime "arrival_time"
    t.integer "wait_time_minutes"
    t.string "care_pathway"
    t.boolean "rp_eligible"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "location_status", default: 0
    t.string "room_number"
    t.datetime "triage_completed_at"
    t.datetime "room_assignment_needed_at"
    t.index ["location_status"], name: "index_patients_on_location_status"
  end

  create_table "rooms", force: :cascade do |t|
    t.string "number", null: false
    t.integer "room_type", default: 0, null: false
    t.integer "status", default: 0
    t.bigint "current_patient_id"
    t.integer "esi_level"
    t.integer "time_in_room"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["current_patient_id"], name: "index_rooms_on_current_patient_id"
    t.index ["number"], name: "index_rooms_on_number", unique: true
    t.index ["room_type"], name: "index_rooms_on_room_type"
    t.index ["status"], name: "index_rooms_on_status"
  end

  create_table "vitals", force: :cascade do |t|
    t.bigint "patient_id", null: false
    t.integer "heart_rate"
    t.integer "blood_pressure_systolic"
    t.integer "blood_pressure_diastolic"
    t.integer "respiratory_rate"
    t.float "temperature"
    t.integer "spo2"
    t.float "weight"
    t.datetime "recorded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["patient_id"], name: "index_vitals_on_patient_id"
  end

  add_foreign_key "care_pathway_clinical_endpoints", "care_pathways"
  add_foreign_key "care_pathway_orders", "care_pathways"
  add_foreign_key "care_pathway_procedures", "care_pathways"
  add_foreign_key "care_pathway_steps", "care_pathways"
  add_foreign_key "care_pathways", "patients"
  add_foreign_key "events", "patients"
  add_foreign_key "nursing_tasks", "patients"
  add_foreign_key "rooms", "patients", column: "current_patient_id"
  add_foreign_key "vitals", "patients"
end
