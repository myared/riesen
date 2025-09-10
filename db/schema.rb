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

ActiveRecord::Schema[8.0].define(version: 2025_09_10_190243) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

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
    t.index ["location_status"], name: "index_patients_on_location_status"
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

  add_foreign_key "events", "patients"
  add_foreign_key "vitals", "patients"
end
