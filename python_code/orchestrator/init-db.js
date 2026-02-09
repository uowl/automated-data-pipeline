import { initSchema, closeDb } from './db.js';

console.log('Initializing pipeline database (SQLite)...');
initSchema();
closeDb();
console.log('Done. Database ready.');
