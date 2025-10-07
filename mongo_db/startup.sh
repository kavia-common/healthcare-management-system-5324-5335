#!/bin/bash
# MongoDB schema, index, and optional seed application script
# - Does NOT start MongoDB server
# - Reads connection either from db_connection.txt or .env (with sensible defaults)
# - Applies JSON Schema validators and indexes from schema/*.json
# - Optionally seeds documents idempotently when DB_SEED="true"

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "${SCRIPT_DIR}"

echo "== MongoDB setup: applying validators, indexes, and optional seed =="

# Load env if present
if [ -f ".env" ]; then
  echo "Loading environment from .env"
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

# Defaults
MONGODB_URL="${MONGODB_URL:-mongodb://localhost:5000}"
MONGODB_DB="${MONGODB_DB:-myapp}"
MONGODB_PORT="${MONGODB_PORT:-5000}"
MONGODB_USER="${MONGODB_USER:-appuser}"
MONGODB_PASSWORD="${MONGODB_PASSWORD:-dbuser123}"
DB_SEED="${DB_SEED:-false}"

# Check mongosh
if ! command -v mongosh >/dev/null 2>&1; then
  echo "⚠ mongosh not found. Please install MongoDB Shell (mongosh) to apply schema and seed."
  echo "   Skipping schema/index/seed application."
  exit 0
fi

# Determine connection string
CONN_STR=""
if [ -f "db_connection.txt" ]; then
  # Expecting format: 'mongosh <connection-string>'
  echo "Using connection from db_connection.txt"
  # Extract anything after leading 'mongosh '
  CONN_STR="$(sed 's/^mongosh[[:space:]]\+//' db_connection.txt | tr -d '\n' | tr -d '\r')"
else
  # Construct from env variables (assumes credentials may be embedded in URL)
  CONN_STR="${MONGODB_URL%/}/${MONGODB_DB}"
fi

if [ -z "$CONN_STR" ]; then
  echo "✗ Could not determine a MongoDB connection string."
  exit 1
fi

echo "Connection: ${CONN_STR}"

# Ensure schema files exist
if [ ! -f "schema/collections.json" ] || [ ! -f "schema/indexes.json" ]; then
  echo "✗ Missing schema files. Ensure schema/collections.json and schema/indexes.json exist."
  exit 1
fi

# Apply validators, create collections if missing, and create indexes
echo "Applying collection validators and indexes..."
mongosh "${CONN_STR}" <<'MONGO'
(function() {
  function log(msg) { print("[setup] " + msg); }
  function tryRun(fn, desc) {
    try { fn(); log("✓ " + desc); }
    catch (e) { log("⚠ " + desc + " failed: " + e.message); }
  }

  // Load JSON files
  const collSpecPath = 'schema/collections.json';
  const idxSpecPath = 'schema/indexes.json';

  let collSpec, idxSpec;
  try {
    collSpec = JSON.parse(cat(collSpecPath));
  } catch (e) {
    print("✗ Failed to read/parse " + collSpecPath + ": " + e.message);
    quit(1);
  }
  try {
    idxSpec = JSON.parse(cat(idxSpecPath));
  } catch (e) {
    print("✗ Failed to read/parse " + idxSpecPath + ": " + e.message);
    quit(1);
  }

  const existing = db.getCollectionNames();

  // Apply validators
  (collSpec.collections || []).forEach(spec => {
    const name = spec.name;
    const validator = spec.validator || {};
    if (!name) return;

    if (existing.indexOf(name) !== -1) {
      tryRun(
        () => db.runCommand({ collMod: name, validator: validator, validationLevel: "moderate" }),
        "Updated validator for collection " + name
      );
    } else {
      tryRun(
        () => db.createCollection(name, { validator: validator, validationLevel: "moderate" }),
        "Created collection " + name + " with validator"
      );
    }
  });

  // Create indexes
  (idxSpec.indexes || []).forEach(ix => {
    if (!ix || !ix.collection || !ix.keys) return;
    tryRun(
      () => db.getCollection(ix.collection).createIndex(ix.keys, ix.options || {}),
      "Created index on " + ix.collection + " keys: " + tojson(ix.keys)
    );
  });

  print("[setup] Validators and indexes applied.");
})();
MONGO

# Optional seeding
if [ "${DB_SEED}" = "true" ]; then
  if [ ! -f "seed/seed_data.json" ]; then
    echo "✗ DB_SEED is true but seed/seed_data.json not found. Skipping seeding."
  else
    echo "Seeding database documents (idempotent upserts)..."
    mongosh "${CONN_STR}" <<'MONGO'
(function() {
  function log(msg) { print("[seed] " + msg); }
  function toObjId(id) { try { return ObjectId(id); } catch (e) { return id; } }

  function convertTypes(doc) {
    // Convert ISO date string fields to Date where appropriate
    const dateKeys = ['createdAt', 'updatedAt', 'scheduledAt', 'expiresAt', 'dob', 'at'];
    const idKeys = ['userId', 'patientId', 'doctorId', 'actorId', '_id'];

    const out = Object.assign({}, doc);
    Object.keys(out).forEach(k => {
      if (idKeys.indexOf(k) !== -1 && typeof out[k] === 'string') {
        out[k] = toObjId(out[k]);
      } else if (dateKeys.indexOf(k) !== -1 && typeof out[k] === 'string') {
        out[k] = new Date(out[k]);
      } else if (out[k] && typeof out[k] === 'object' && !Array.isArray(out[k])) {
        out[k] = convertTypes(out[k]);
      } else if (Array.isArray(out[k])) {
        out[k] = out[k].map(v => (typeof v === 'object' && v !== null ? convertTypes(v) : v));
      }
    });
    return out;
  }

  let seed;
  try {
    seed = JSON.parse(cat('seed/seed_data.json'));
  } catch (e) {
    print("✗ Failed to read/parse seed/seed_data.json: " + e.message);
    quit(1);
  }

  function upsertMany(collName, docs) {
    if (!docs || !docs.length) return;
    const coll = db.getCollection(collName);
    docs.forEach(d => {
      const doc = convertTypes(d);
      const idFilter = doc._id ? { _id: doc._id } : doc._id;
      // Use $setOnInsert to avoid overwriting existing data
      const res = coll.updateOne(idFilter, { $setOnInsert: doc }, { upsert: true });
      log(collName + " upsert: " + tojson(res));
    });
  }

  upsertMany('users', seed.users || []);
  upsertMany('doctors', seed.doctors || []);
  upsertMany('patients', seed.patients || []);
  upsertMany('consultations', seed.consultations || []);
  upsertMany('medical_records', seed.medical_records || []);
  upsertMany('refresh_tokens', seed.refresh_tokens || []);
  upsertMany('audit_logs', seed.audit_logs || []);

  print("[seed] Seeding complete.");
})();
MONGO
  fi
else
  echo "DB_SEED is not 'true'; skipping seeding."
fi

# Output helpful environment files
echo "Writing db_visualizer/mongodb.env aligned with current env values..."
cat > db_visualizer/mongodb.env <<EOF
export MONGODB_URL="${MONGODB_URL%/}/?authSource=admin"
export MONGODB_DB="${MONGODB_DB}"
EOF

echo ""
echo "== Completed MongoDB schema/index application =="
echo "Database: ${MONGODB_DB}"
echo "MONGODB_URL: ${MONGODB_URL}"
echo "DB_SEED: ${DB_SEED}"
echo ""
echo "To connect manually:"
echo "  mongosh ${CONN_STR}"
