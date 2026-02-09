/**
 * Pipeline logger: writes to PipelineLogs table and console.
 * Level: Info, Warning, Error
 */

function now() {
  return new Date().toISOString();
}

/**
 * @param {import('better-sqlite3').Database} db
 * @param {string} runId
 * @param {Object} options
 * @param {string} options.level - Info | Warning | Error
 * @param {string} options.message
 * @param {string} [options.pipelineName]
 * @param {number} [options.stepNumber]
 * @param {string} [options.stepName]
 * @param {string} [options.details]
 */
export function log(db, runId, options) {
  const { level = 'Info', message, pipelineName = null, stepNumber = null, stepName = null, details = null } = options;
  const logAt = now();
  const prefix = level === 'Error' ? 'ERROR' : level === 'Warning' ? 'WARN' : 'INFO';
  const stepPart = stepNumber != null ? ` [Step ${stepNumber}${stepName ? ` ${stepName}` : ''}]` : '';
  console.log(`${logAt} ${prefix}${stepPart} ${message}`);
  if (details && (level === 'Error' || level === 'Warning')) console.log(`  ${details}`);
  try {
    db.prepare(`
      INSERT INTO PipelineLogs (RunId, PipelineName, LogAt, Level, StepNumber, StepName, Message, Details)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run(runId, pipelineName, logAt, level, stepNumber, stepName, message, details);
  } catch (err) {
    console.error('Logger failed to write to DB:', err.message);
  }
}
