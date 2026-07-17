import { openDb } from "./db.js";
import { createApp } from "./app.js";
import { DB_PATH, PORT, TIME_SCALE } from "./config.js";

const db = openDb(DB_PATH);
const app = createApp(db);

const server = app.listen(PORT, () => {
  console.log(`🛒 Straßenimperium läuft auf http://localhost:${PORT}`);
  console.log(`   Datenbank: ${DB_PATH}`);
  if (TIME_SCALE !== 1) {
    console.log(`   ⚠️  DEV_TIME_SCALE=${TIME_SCALE} — Zeitraffer aktiv (nur für Entwicklung!)`);
  }
});

function shutdown() {
  console.log("Fahre herunter …");
  server.close(() => {
    db.close();
    process.exit(0);
  });
}
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
