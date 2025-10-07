# MongoDB - Healthcare Management System

This folder contains MongoDB initialization, schema documentation, and utility scripts for the Healthcare application.

Key highlights:
- Database name: `healthcare`
- App user: `appuser` (password: `dbuser123`)
- Admin user: `appuser` (granted admin roles during bootstrap)
- Port: `5000`

Connection URIs:
- Shell connection:
  mongosh mongodb://appuser:dbuser123@localhost:5000/healthcare?authSource=admin

- App-level URL (db_visualizer and backend reference):
  mongodb://appuser:dbuser123@localhost:5000/?authSource=admin
  Database: healthcare

Schemas and Indexes:
- Documentation is available at: mongo_db/schemas/collections.json
- Collections:
  - users
    - Unique index: email
    - Index: role
  - patients
    - Unique index: user_id
    - Index: last_name + first_name
  - doctors
    - Unique index: user_id
    - Unique index: license_no
    - Index: specialization
  - consultations
    - Indexes: patient_id, doctor_id, scheduled_at, composite (patient_id, doctor_id, scheduled_at)
  - medical_records
    - Indexes: patient_id, doctor_id, consultation_id, record_type, created_at

Seed data:
- Minimal sample documents for a patient and a doctor are provided:
  - File: mongo_db/seed/seed_data.json
- The startup script will attempt an idempotent import when the file is present.

Startup and provisioning:
- The startup script:
  - Starts a local mongod on port 5000
  - Ensures admin/app users
  - Ensures collections and indexes
  - Optionally imports seed data

Environment hints:
- Node viewer (db_visualizer) expects:
  export MONGODB_URL="mongodb://appuser:dbuser123@localhost:5000/?authSource=admin"
  export MONGODB_DB="healthcare"

Backup and Restore:
- Backup:
  Run from this directory:
    ./backup_db.sh
  It automatically detects MongoDB and creates:
    database_backup.archive

- Restore:
  Run from this directory:
    ./restore_db.sh
  It detects the archive and restores the database (drop + restore).

Notes:
- Do not hardcode secrets in production. Use environment variables.
- For the backend, configure the MongoDB connection using environment variables and the service URL in deployment.
