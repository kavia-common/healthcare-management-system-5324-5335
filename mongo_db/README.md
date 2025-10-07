# MongoDB - Healthcare Management System

This folder contains MongoDB initialization, schema documentation, and utility scripts for the Healthcare application.

Key highlights:
- Database name: `healthcare`
- App user: `appuser` (password configured via env at runtime; example shown below)
- Admin user: `appuser` (granted admin roles during bootstrap)
- Preview Port: `5001`

Connection URIs:
- Shell connection (example):
  mongosh mongodb://appuser:dbuser123@localhost:5001/healthcare?authSource=admin

- App-level URL (db_visualizer and backend reference via env):
  MONGODB_URL=mongodb://appuser:dbuser123@localhost:5001/?authSource=admin
  MONGODB_DB=healthcare

Environment:
- Provide a .env file or export variables as needed:
  - MONGODB_URL (e.g., mongodb://appuser:dbuser123@localhost:5001/?authSource=admin)
  - MONGODB_DB (e.g., healthcare)
- An example file is provided at: mongo_db/.env.example

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
- The startup script attempts an idempotent import when the file is present. If the file is removed, the step is skipped.

Startup and provisioning:
- The startup script:
  - Starts a local mongod on 0.0.0.0:5001
  - Ensures admin/app users (idempotent)
  - Ensures collections and indexes (idempotent)
  - Optionally imports seed data if present (idempotent)

Environment hints:
- Node viewer (db_visualizer) expects:
  export MONGODB_URL="mongodb://appuser:dbuser123@localhost:5001/?authSource=admin"
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
