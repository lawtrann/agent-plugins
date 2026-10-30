import { expect, test } from 'claude-code/testing'

test('passes tool calls through', async ($, on) => {
  on('tool.call', () => ({ result: 'ok' }))
  const out = await $.tool.call({ tool: 'Bash', command: 'ls' })
  expect(out).toEqual({ result: 'ok' })
})
