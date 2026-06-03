#!/usr/bin/env node

const webhookUrl = process.env.SLACK_WEBHOOK_URL;

if (!webhookUrl) {
  console.log('SLACK_WEBHOOK_URL is not set; skipping Slack notification.');
  process.exit(0);
}

const provider = process.env.CI_PROVIDER || 'CI';
const status = (process.env.STATUS || 'success').toLowerCase();
const title = process.env.TITLE || `${provider} build ${status}`;
const url = process.env.RUN_URL || process.env.BUILD_URL || '';
const ref = process.env.REF_NAME || process.env.CM_TAG || process.env.CM_BRANCH || '';
const sha = (process.env.SHA || process.env.CM_COMMIT || '').slice(0, 12);
const step = process.env.STEP_NAME || '';
const summary = process.env.SUMMARY || '';
const version = process.env.VERSION_COMPILED || process.env.APP_VERSION || process.env.SDK_VERSION || '';
const durationSeconds = process.env.DURATION_SECONDS || '';
const testsPassed = process.env.TESTS_PASSED || '';
const jobResults = process.env.JOB_RESULTS ? JSON.parse(process.env.JOB_RESULTS) : null;

function formatDuration(seconds) {
  const parsed = Number(seconds);
  if (!Number.isFinite(parsed) || parsed < 0) return '';
  const rounded = Math.round(parsed);
  const minutes = Math.floor(rounded / 60);
  const remainingSeconds = rounded % 60;
  return minutes > 0 ? `${minutes}m ${remainingSeconds}s` : `${remainingSeconds}s`;
}

const state = status === 'success' ? 'SUCCESS' : 'FAILURE';
const color = status === 'success' ? '#2eb67d' : '#e01e5a';

const fields = [
  `*Status:* ${state}`,
  ref ? `*Ref:* ${ref}` : null,
  sha ? `*SHA:* ${sha}` : null,
  step ? `*Step:* ${step}` : null,
  version ? `*Version compiled:* ${version}` : null,
  durationSeconds ? `*Compile time:* ${formatDuration(durationSeconds)}` : null,
  testsPassed ? `*Passed tests:*\n${testsPassed}` : null,
].filter(Boolean);

if (jobResults) {
  const details = Object.entries(jobResults)
    .map(([name, result]) => `- ${name}: ${result.result}`)
    .join('\n');
  if (details) fields.push(`*Jobs:*\n${details}`);
}

const text = `${state}: ${title}${url ? ` ${url}` : ''}`;
const payload = {
  text,
  attachments: [
    {
      color,
      blocks: [
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: `*${title}*`,
          },
        },
        {
          type: 'section',
          text: {
            type: 'mrkdwn',
            text: fields.join('\n'),
          },
        },
        summary
          ? {
              type: 'section',
              text: {
                type: 'mrkdwn',
                text: summary,
              },
            }
          : null,
        url
          ? {
              type: 'section',
              text: {
                type: 'mrkdwn',
                text: `<${url}|Open build>`,
              },
            }
          : null,
      ].filter(Boolean),
    },
  ],
};

const response = await fetch(webhookUrl, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify(payload),
});

if (!response.ok) {
  const body = await response.text();
  throw new Error(`Slack notification failed: ${response.status} ${body}`);
}

console.log('Slack notification sent.');
