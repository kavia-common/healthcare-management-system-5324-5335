# MongoDB Schema, Indexes, and Seeding

This folder configures MongoDB for the Healthcare Management System, including:
- JSON Schema validators for all collections
- Indexes (unique, compound, TTL)
- Optional seed data for bootstrapping
- Environment variable scaffolding
- A startup script to apply validators, create indexes, and seed (optional)

Contents:
- schema/collections.json — JSON Schema validators per collection
- schema/indexes.json — Index definitions per collection
- seed/seed_data.json — Sample bootstrap data
- .env.example — Example environment variables
- startup.sh — Applies validators, indexes, and optional seed
- db_visualizer/mongodb.env — Environment vars for the DB viewer

Environment variables:
- MONGODB_URL — Base MongoDB connection string (e.g., mongodb://user:pass@localhost:5001/?authSource=admin)
- MONGODB_DB — Database name (default: myapp)
- MONGODB_PORT — Port MongoDB service listens on (default: 5001)
- MONGODB_USER — Admin/App user (default: appuser)
- MONGODB_PASSWORD — Password (default: dbuser123)
- DB_SEED — If "true", seed data will be upserted (default: false)

How to use:
1) Configure environment:
   - Copy .env.example to .env and adjust values, or use defaults.
   - Optionally ensure db_connection.txt contains a valid connection command line for mongosh:
     e.g., mongosh mongodb://appuser:dbuser123@localhost:5001/myapp?authSource=admin

2) Run the startup script:
   - cd healthcare-management-system-5324-5335/mongo_db
   - chmod +x startup.sh
   - ./startup.sh

What startup.sh does:
- Loads .env if present and sets sensible defaults if not
- Tries to use db_connection.txt (if present) to connect; falls back to MONGODB_URL and MONGODB_DB
- Applies JSON Schema validators and creates collections if missing
- Creates indexes as defined in schema/indexes.json
- Optionally seeds the database if DB_SEED is "true" (idempotent upserts)
- Prints completion logs

Notes:
- The script does not start MongoDB services; it only applies schema and seed to an already running MongoDB.
- If mongosh is not installed or connection fails, it will print helpful messages and exit gracefully.

Seeding:
- Enabled by setting DB_SEED="true" in .env before running the script
- Uses stable ObjectIds to avoid duplicates
- Will upsert users, doctors, patients, consultations, medical_records, refresh_tokens (optional), and audit_logs

Troubleshooting:
- Ensure mongosh is installed and accessible
- Ensure the MongoDB instance is reachable at MONGODB_URL / db_connection.txt
- Ensure credentials are correct if authentication is enabled

Security:
- Do not commit .env files with real credentials
- Use the provided .env.example to understand required variables
