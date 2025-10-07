#!/bin/bash

# MongoDB startup script following the same pattern
# Note: Database name aligned with project domain
# Allow environment overrides; fall back to defaults if not set
DB_NAME="${MONGODB_DB:-healthcare}"
DB_USER="${MONGODB_ADMIN_USER:-appuser}"
DB_PASSWORD="${MONGODB_ADMIN_PASSWORD:-dbuser123}"
DB_PORT="${MONGODB_PORT:-5001}"

echo "Starting MongoDB setup..."

# Check if MongoDB is already running
if mongosh --port ${DB_PORT} --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
    echo "MongoDB is already running on port ${DB_PORT}!"
    
    # Try to verify the database exists and user can connect
    if mongosh "mongodb://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}?authSource=admin" --eval "db.getName()" > /dev/null 2>&1; then
        echo "Database ${DB_NAME} is accessible with user ${DB_USER}."
    else
        echo "MongoDB is running but authentication might not be configured."
    fi
    
    echo ""
    echo "Database: ${DB_NAME}"
    echo "Admin user: ${DB_USER} (password: ${DB_PASSWORD})"
    echo "App user: appuser (password: ${DB_PASSWORD})"
    echo "Port: ${DB_PORT}"
    echo ""
    
    # Check if connection info file exists
    if [ -f "db_connection.txt" ]; then
        echo "To connect to the database, use:"
        echo "$(cat db_connection.txt)"
    else
        echo "To connect to the database, use:"
        echo "mongosh mongodb://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}?authSource=admin"
    fi
    
    echo ""
    echo "Script stopped - MongoDB server already running."
    exit 0
fi

# Check if MongoDB is running on a different port
if pgrep -x mongod > /dev/null; then
    # Get the port of the running MongoDB instance
    MONGO_PID=$(pgrep -x mongod)
    CURRENT_PORT=$(sudo lsof -Pan -p $MONGO_PID -i | grep -o ":[0-9]*" | grep -o "[0-9]*" | head -1)
    
    if [ "$CURRENT_PORT" = "${DB_PORT}" ]; then
        echo "MongoDB is already running on port ${DB_PORT}!"
        echo "Script stopped - server already running."
        exit 0
    else
        echo "MongoDB is running on different port ($CURRENT_PORT), stopping it..."
        sudo pkill -x mongod
        sleep 2
    fi
fi

# Clean up any existing socket files
sudo rm -f /tmp/mongodb-*.sock 2>/dev/null

# Start MongoDB server without authentication initially using nohup
echo "Starting MongoDB server..."
nohup sudo mongod --dbpath /var/lib/mongodb --port ${DB_PORT} --bind_ip 0.0.0.0 --unixSocketPrefix /var/run/mongodb > /var/lib/mongodb/mongod.log 2>&1 &

# Wait for MongoDB to start
echo "Waiting for MongoDB to start..."
sleep 5

# Check if MongoDB is running
for i in {1..15}; do
    if mongosh --port ${DB_PORT} --eval "db.adminCommand('ping')" > /dev/null 2>&1; then
        echo "MongoDB is ready!"
        break
    fi
    echo "Waiting... ($i/15)"
    sleep 2
done

# Create database and user
echo "Setting up database and user..."
mongosh --port ${DB_PORT} << EOF
// Switch to admin database for user creation
use admin

// Create admin user if it doesn't exist
if (db.getUser("${DB_USER}") == null) {
    db.createUser({
        user: "${DB_USER}",
        pwd: "${DB_PASSWORD}",
        roles: [
            { role: "userAdminAnyDatabase", db: "admin" },
            { role: "readWriteAnyDatabase", db: "admin" }
        ]
    });
}

// Switch to target database
use ${DB_NAME}

// Create application user for specific database
if (db.getUser("appuser") == null) {
    db.createUser({
        user: "appuser",
        pwd: "${DB_PASSWORD}",
        roles: [
            { role: "readWrite", db: "${DB_NAME}" }
        ]
    });
}

print("MongoDB users created/ensured.");
EOF

# Ensure collections and indexes using mongosh one-liners (MongoDB Container CRITICAL Rules)
echo "Creating collections and indexes..."

# Create database explicitly (no-op if exists)
functions=( \
'mongosh --port '"${DB_PORT}"' -e "use '"${DB_NAME}"'"' \
)

# Users indexes
functions+=( \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").createCollection(\"users\")"' \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").users.createIndex({email:1},{unique:true,name:\"uniq_email\"})"' \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").users.createIndex({role:1},{name:\"idx_role\"})"' \
)

# Patients indexes
functions+=( \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").createCollection(\"patients\")"' \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").patients.createIndex({user_id:1},{unique:true,name:\"uniq_patient_user\"})"' \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").patients.createIndex({last_name:1,first_name:1},{name:\"idx_patient_name\"})"' \
)

# Doctors indexes
functions+=( \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").createCollection(\"doctors\")"' \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").doctors.createIndex({user_id:1},{unique:true,name:\"uniq_doctor_user\"})"' \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").doctors.createIndex({license_no:1},{unique:true,name:\"uniq_license_no\"})"' \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").doctors.createIndex({specialization:1},{name:\"idx_specialization\"})"' \
)

# Consultations indexes
functions+=( \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").createCollection(\"consultations\")"' \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").consultations.createIndex({patient_id:1},{name:\"idx_consult_patient\"})"' \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").consultations.createIndex({doctor_id:1},{name:\"idx_consult_doctor\"})"' \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").consultations.createIndex({scheduled_at:-1},{name:\"idx_scheduled_at\"})"' \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").consultations.createIndex({patient_id:1,doctor_id:1,scheduled_at:-1},{name:\"idx_patient_doctor_date\"})"' \
)

# Medical records indexes
functions+=( \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").createCollection(\"medical_records\")"' \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").medical_records.createIndex({patient_id:1},{name:\"idx_record_patient\"})"' \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").medical_records.createIndex({doctor_id:1},{name:\"idx_record_doctor\"})"' \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").medical_records.createIndex({consultation_id:1},{name:\"idx_record_consult\"})"' \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").medical_records.createIndex({record_type:1},{name:\"idx_record_type\"})"' \
'mongosh --port '"${DB_PORT}"' -e "db.getSiblingDB(\"'"${DB_NAME}"'\").medical_records.createIndex({created_at:-1},{name:\"idx_record_created_at\"})"' \
)

for cmd in "${functions[@]}"; do
  eval "$cmd" >/dev/null 2>&1 || true
done

# Optional seed import if file exists
if [ -f "mongo_db/seed/seed_data.json" ]; then
  echo "Importing seed data..."
  # Use mongoimport per collection, parsing the JSON file with jq if available; otherwise fallback to mongosh inserts
  if command -v jq >/dev/null 2>&1; then
    for coll in users patients doctors consultations medical_records; do
      jq -c --arg coll "$coll" '.[$coll][]' mongo_db/seed/seed_data.json | while read -r doc; do
        mongosh --port ${DB_PORT} -e "db.getSiblingDB(\"${DB_NAME}\").getCollection(\"$coll\").updateOne({_id: $(echo "$doc" | jq '.["_id"]')}, { \$setOnInsert: $(echo "$doc" | jq 'del(._id)') , \$set: {} }, { upsert: true })" >/dev/null 2>&1 || true
      done
    done
  else
    # Lightweight fallback: insert whole arrays with mongosh by loading file
    mongosh --port ${DB_PORT} <<'EOJS' >/dev/null 2>&1
      const fs = require('fs');
      const path = 'mongo_db/seed/seed_data.json';
      if (fs.existsSync(path)) {
        const raw = fs.readFileSync(path, 'utf8');
        const data = JSON.parse(raw);
        const dbname = 'healthcare';
        const dbh = db.getSiblingDB(dbname);
        function upsertMany(coll, arr) {
          if (!arr) return;
          arr.forEach(doc => {
            const id = doc._id;
            const copy = Object.assign({}, doc);
            delete copy._id;
            dbh.getCollection(coll).updateOne({_id: id}, { $setOnInsert: copy, $set: {} }, { upsert: true });
          });
        }
        upsertMany('users', data.users);
        upsertMany('patients', data.patients);
        upsertMany('doctors', data.doctors);
        upsertMany('consultations', data.consultations);
        upsertMany('medical_records', data.medical_records);
      }
EOJS
  fi
  echo "Seed data import attempted (idempotent)."
else
  echo "No seed file found at mongo_db/seed/seed_data.json - skipping import."
fi

echo "MongoDB collections and indexes ensured."
# Save connection command to a file
echo "mongosh mongodb://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/${DB_NAME}?authSource=admin" > db_connection.txt
echo "Connection string saved to db_connection.txt"

# Save environment variables to a file
cat > db_visualizer/mongodb.env << EOF
export MONGODB_URL="mongodb://${DB_USER}:${DB_PASSWORD}@localhost:${DB_PORT}/?authSource=admin"
export MONGODB_DB="${DB_NAME}"
EOF

echo "MongoDB setup complete!"
echo "Database: ${DB_NAME}"
echo "Admin user: ${DB_USER} (password: ${DB_PASSWORD})"
echo "App user: appuser (password: ${DB_PASSWORD})"
echo "Port: ${DB_PORT}"
echo ""

echo "Environment variables saved to db_visualizer/mongodb.env"
echo "To use with Node.js viewer, run: source db_visualizer/mongodb.env"

echo "To connect to the database, use one of the following commands:"
echo "mongosh -u ${DB_USER} -p ${DB_PASSWORD} --port ${DB_PORT} --authenticationDatabase admin ${DB_NAME}"
echo "$(cat db_connection.txt)"

# MongoDB continues running in background
echo ""
echo "MongoDB is running in the background."
echo "You can now start your application."